// CFRunLoopRun
#import <Foundation/Foundation.h>
// all the dispatch stuff.
#import <dispatch/dispatch.h>
// system
#import <stdlib.h>
// open
#import <fcntl.h>
// fprintf, stderr
#import <stdio.h>
// strlen, strdup
#import <string.h>
// setrlimit if fd limit is too low.
#import <sys/resource.h>

#if !__has_feature(objc_arc)
#error "ARC is off"
#endif

static const char* COMMAND;
static int VERBOSE = 0;

// Multiple files can change at once, so use this to prevent submitting
// the command again if we've already put it in the queue.
static int submitted = 0;

static
void
schedule_command(void){
    if(submitted) return;
    submitted = 1;
    dispatch_async(dispatch_get_main_queue(), ^{
        fprintf(stderr, "---\n%s\n", COMMAND);
        system(COMMAND);
        fprintf(stderr, "---\n");
        submitted = 0;
    });
}

static void periodically_retry_watchfile(const char*);

enum WATCHFILEFLAGS {
    WATCHFILE_NONE = 0,
    // Don't print errors when failing to watch.
    WATCHFILE_QUIET_FAIL = 1,
};

static
int
watchfile(const char* filename, enum WATCHFILEFLAGS flags){
    int fd = open(filename, O_EVTONLY); // open for notification only
    if(fd < 0){
        if(!(flags & WATCHFILE_QUIET_FAIL)){
            fprintf(stderr, "Failed to watch '%s': %s\n", filename, strerror(errno));
        }
        return 1;
    }
    if(VERBOSE) fprintf(stderr, "Watching '%s'\n", filename);
    dispatch_source_t source = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_VNODE,
            fd,
            0
            // | DISPATCH_VNODE_ATTRIB, // So touch works as expected.
            | DISPATCH_VNODE_WRITE
            | DISPATCH_VNODE_DELETE
            | DISPATCH_VNODE_RENAME
            | DISPATCH_VNODE_EXTEND,
            dispatch_get_main_queue());

    dispatch_source_set_event_handler(source, ^{
        uintptr_t mask = dispatch_source_get_data(source);
        if(mask & DISPATCH_VNODE_RENAME){
            if(VERBOSE) fprintf(stderr, "'%s' was renamed.\n", filename);
            dispatch_source_cancel(source);
            int closed = close(fd);
            if(closed < 0){
                fprintf(stderr, "Close for %s failed: %s\n", filename, strerror(errno));
            }
            // fprintf(stderr, "Canceling '%s'\n", filename);
            int fail = watchfile(filename, WATCHFILE_QUIET_FAIL);
            if(fail)
                periodically_retry_watchfile(filename);
            else // file exists again
                schedule_command();
            return;
        }
        if(mask & DISPATCH_VNODE_WRITE) {
            if(VERBOSE) fprintf(stderr, "'%s' was written.\n", filename);
        }
        if(mask & DISPATCH_VNODE_EXTEND) {
            if(VERBOSE) fprintf(stderr, "'%s' was extended.\n", filename);
        }
        if(mask & DISPATCH_VNODE_ATTRIB) {
            if(VERBOSE) fprintf(stderr, "'%s' metadata changed.\n", filename);
        }
        if(mask & (DISPATCH_VNODE_DELETE)){
            if(VERBOSE) fprintf(stderr, "'%s' was deleted.\n", filename);
            dispatch_source_cancel(source);
            int closed = close(fd);
            if(closed < 0)
                fprintf(stderr, "Close for %s failed: %s\n", filename, strerror(errno));
            // fprintf(stderr, "Canceling '%s'\n", filename);
            int fail = watchfile(filename, WATCHFILE_QUIET_FAIL);
            if(fail)
                periodically_retry_watchfile(filename);
            else // file exists again
                schedule_command();
            return;
        }
        schedule_command();
        });
    dispatch_resume(source);
    return 0;
}

static
void
periodically_retry_watchfile(const char* filename){
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    // 1 time per second
    uint64_t interval_in_nanoseconds = 1llu*NSEC_PER_SEC;
    // 1/10th of a second
    uint64_t leeway_in_nanoseconds = 1llu*NSEC_PER_SEC/10llu;
    dispatch_source_set_timer(source, DISPATCH_TIME_NOW, interval_in_nanoseconds, leeway_in_nanoseconds);
    dispatch_source_set_event_handler(source, ^{
        int fail = watchfile(filename, WATCHFILE_QUIET_FAIL);
        if(fail) return;
        schedule_command();
        dispatch_source_cancel(source);
        });
    dispatch_resume(source);
}

static
int
set_max_files_to_reasonable_number(void){
    int err;
    struct rlimit rl;
    err = getrlimit(RLIMIT_NOFILE, &rl);
    if(err){
        perror("getrlimit");
        return 1;
    }
    if(rl.rlim_cur < 4192 && rl.rlim_max >= 4192){
        rl.rlim_cur = 4192;
        err = setrlimit(RLIMIT_NOFILE, &rl);
        if(err){
            perror("setrlimit");
            return 1;
        }
    }
    return 0;
}

#ifndef NOMAIN
int
main(int argc, char** argv){
    if(set_max_files_to_reasonable_number() != 0)
        return 1;
    const char* progname = argc? argv[0] : "macwatch";
    if(argc < 2){
        fprintf(stderr, "Usage: %s 'command' files [...]\n", progname);
        return 1;
    }
    VERBOSE = getenv("MACWATCH_VERBOSE")?atoi(getenv("MACWATCH_VERBOSE")):1;
    int nfiles = argc-2;
    char** filenames = argv + 2;
    COMMAND = argv[1];
    for(int i = 0; i < nfiles; i++){
        char* filename = filenames[i];
        int fail = watchfile(filename, WATCHFILE_NONE);
        if(fail)
            periodically_retry_watchfile(filename);
    }
    // Support piping in filenames.
    if(!isatty(STDIN_FILENO)){ // we're being piped to.
        char buff[8192];
        while(fgets(buff, sizeof(buff), stdin)){
            size_t len = strlen(buff);
            if(!len) continue;
            buff[--len] = '\0';
            if(!len) continue;
            char* fn = strdup(buff);
            int fail = watchfile(fn, WATCHFILE_NONE);
            if(fail)
                periodically_retry_watchfile(fn);
        }
    }
    else if(argc < 3){
        fprintf(stderr, "Usage: %s 'command' files [...]\n", progname);
        return 1;
    }
    schedule_command();
#if 0
    dispatch_main();
#else
    CFRunLoopRun();
#endif
    return 0;
}
#endif
