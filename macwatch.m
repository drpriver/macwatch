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
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group, dispatch_get_main_queue(), ^{
        fprintf(stderr, "---\n%s\n", COMMAND);
        system(COMMAND);
        fprintf(stderr, "---\n");
        submitted = 0;
    });
}

static
int
watchfile(const char* filename){
    int fd = open(filename, O_EVTONLY); // open for notification only
    if(fd < 0){
        fprintf(stderr, "Failed to watch '%s'\n", filename);
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
            // FIXME: this isn't quite right.
            // We assume that we will get a delete right after and then we can
            // rewatch the new file, but that could never happen.
            //
            // We should probably just treat this like a delete and cancel the source
            // and then kick off a timer that looks to see if the file is created.
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
            schedule_command();
            dispatch_source_cancel(source);
            int closed  =close(fd);
            if(closed < 0)
                fprintf(stderr, "Close for %s failed.\n", filename);
            fprintf(stderr, "Canceling '%s'\n", filename);
            // This isn't correct as the file may get deleted then recreated,
            // but with a long enough timeframe that we never start watching it
            // again.
            int fail = watchfile(filename);
            // This obviously isn't quite correct.
            // If we fail we should basically create a timed event to poll for
            // if the file is later created or something simmilar.
            (void)fail;
            return;
        }
        schedule_command();
        });
    dispatch_resume(source);
    return 0;
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
        int fail = watchfile(filename);
        // Same comment on correctness. If we fail to watch we should make a
        // timer event to poll for if the file is later created.
        (void)fail;
    }
    // I'm not sure why, but if you use dispatch_main to drive the event loop
    // then you stop being able to kill the program with ctrl-c or even ctrl-\
    // Possibly you need to subscribe to signal events and call exit?  But for
    // now, just use CFRunLoopRun because who cares.
#if 0
    dispatch_main();
#else
    CFRunLoopRun();
#endif
    return 0;
}
