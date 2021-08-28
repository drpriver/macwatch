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

#if !__has_feature(objc_arc)
#error "ARC is off"
#endif

static const char* COMMAND;

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

static void timer_retry_watchfile(const char*);

enum WATCHFILEFLAGS {
    WATCHFILE_NONE = 0,
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
    fprintf(stderr, "Watching '%s'\n", filename);
    dispatch_source_t source = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_VNODE,
            fd,
            0
            | DISPATCH_VNODE_WRITE
            | DISPATCH_VNODE_DELETE
            | DISPATCH_VNODE_RENAME
            | DISPATCH_VNODE_EXTEND
            | DISPATCH_VNODE_ATTRIB, // So touch works as expected.
            dispatch_get_main_queue());

    dispatch_source_set_event_handler(source, ^{
        uintptr_t mask = dispatch_source_get_data(source);
        if(mask & DISPATCH_VNODE_RENAME){
            fprintf(stderr, "'%s' was renamed.\n", filename);
            dispatch_source_cancel(source);
            int closed = close(fd);
            if(closed < 0){
                fprintf(stderr, "Close for %s failed: %s\n", filename, strerror(errno));
                }
            // fprintf(stderr, "Canceling '%s'\n", filename);
            int fail = watchfile(filename, WATCHFILE_QUIET_FAIL);
            if(fail)
                timer_retry_watchfile(filename);
            else // file exists again
                schedule_command();
            return;
        }
        if(mask & DISPATCH_VNODE_WRITE) {
            fprintf(stderr, "'%s' was written.\n", filename);
        }
        if(mask & DISPATCH_VNODE_EXTEND) {
            fprintf(stderr, "'%s' was extended.\n", filename);
        }
        if(mask & DISPATCH_VNODE_ATTRIB) {
            fprintf(stderr, "'%s' metadata changed.\n", filename);
        }
        if(mask & (DISPATCH_VNODE_DELETE)){
            fprintf(stderr, "'%s' was deleted.\n", filename);
            dispatch_source_cancel(source);
            int closed = close(fd);
            if(closed < 0)
                fprintf(stderr, "Close for %s failed: %s\n", filename, strerror(errno));
            // fprintf(stderr, "Canceling '%s'\n", filename);
            int fail = watchfile(filename, WATCHFILE_QUIET_FAIL);
            if(fail)
                timer_retry_watchfile(filename);
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
timer_retry_watchfile(const char* filename){
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

int
main(int argc, char** argv){
    if(argc < 3){
        const char* progname = argc? argv[0] : "macwatch";
        fprintf(stderr, "Usage: %s 'command' files ...\n", progname);
        return 1;
    }
    int nfiles = argc-2;
    char** filenames = argv + 2;
    COMMAND = argv[1];
    for(int i = 0; i < nfiles; i++){
        char* filename = filenames[i];
        int fail = watchfile(filename, WATCHFILE_NONE);
        if(fail){
            timer_retry_watchfile(filename);
        }
    }
#if 0
    dispatch_main();
#else
    CFRunLoopRun();
#endif
    return 0;
}
