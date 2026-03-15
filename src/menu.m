#import <Cocoa/Cocoa.h>

void setupMacOSMenu(void) {
    NSApplication *app = [NSApplication sharedApplication];

    NSMenu *menubar = [NSMenu new];
    NSMenuItem *appMenuItem = [NSMenuItem new];
    [menubar addItem:appMenuItem];
    [app setMainMenu:menubar];

    NSMenu *appMenu = [NSMenu new];
    NSString *appName = @"Just Draw";

    NSMenuItem *quitItem = [[NSMenuItem alloc]
        initWithTitle:[@"Quit " stringByAppendingString:appName]
        action:@selector(terminate:)
        keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
    [appMenuItem setSubmenu:appMenu];
}
