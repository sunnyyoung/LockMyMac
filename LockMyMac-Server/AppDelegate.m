//
//  AppDelegate.m
//  LockMyMac-Server
//
//  Created by Sunnyyoung on 2016/11/15.
//
//

#import "AppDelegate.h"

static NSString * const NetServiceDomain = @"local.";
static NSString * const NetServiceType = @"_LockMyMac._tcp.";

static dispatch_queue_t server_socket_queue() {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_queue_attr_t attr = DISPATCH_QUEUE_SERIAL;
        attr = dispatch_queue_attr_make_with_qos_class(attr, QOS_CLASS_BACKGROUND, 0);
        queue = dispatch_queue_create("net.sunnyyoung.LockMyMac-Server.socket", attr);
    });
    return queue;
}

@interface AppDelegate () <NSNetServiceDelegate, GCDAsyncSocketDelegate>

// UI
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenuItem *switchMenuItem;

// Property
@property (nonatomic, strong) NSNetService *netService;
@property (nonatomic, strong) GCDAsyncSocket *socket;
@property (nonatomic, strong) NSMutableArray<GCDAsyncSocket *> *pool;
@property (nonatomic, assign) BOOL isStart;

@end

@implementation AppDelegate

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if (self) {
        _socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:server_socket_queue()];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self statusItem];
}

#pragma mark - NetService Delegate

- (void)netServiceDidPublish:(NSNetService *)sender {
    NSLog(@"Bonjour Service Published: domain(%@) type(%@) name(%@) port(%i)", [sender domain], [sender type], [sender name], (int)[sender port]);
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    NSLog(@"Failed to Publish Service: domain(%@) type(%@) name(%@) - %@", [sender domain], [sender type], [sender name], errorDict);
}

#pragma mark - Socket Delegate

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket {
    @synchronized (self.pool) {
        [self.pool addObject:newSocket];
    }
    [newSocket readDataWithTimeout:-1 tag:0];
    NSLog(@"Socket connected: %@", newSocket.connectedHost);
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    @synchronized (self.pool) {
        [self.pool removeObject:sock];
    }
    NSLog(@"Socket disconnected: %@", sock.connectedHost);
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    [sock readDataWithTimeout:-1 tag:0];
    if (!data) {
        return;
    }
    NSString *command = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [command isEqualToString:@"LOCK\n"]?[self lockScreen]:nil;
    [sock writeData:[@"Success\n" dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1 tag:0];
}

#pragma mark - Event Response

- (void)switchAction:(id)sender {
    if (!self.isStart) {
        NSError *error = nil;
        [self.socket acceptOnPort:0 error:&error];
        if (error) {
            NSLog(@"Error when starting: %@", error);
            return;
        }
        self.netService = [[NSNetService alloc] initWithDomain:NetServiceDomain type:NetServiceType name:@"" port:self.socket.localPort];
        self.netService.delegate = self;
        [self.netService publish];
        self.isStart = YES;
    } else {
        [self.socket disconnect];
        @synchronized (self.pool) {
            for (GCDAsyncSocket *socket in self.pool) {
                [socket disconnect];
            }
        }
        [self.netService stop];
        self.isStart = NO;
    }
}

#pragma mark - Private method

- (void)lockScreen {
    NSBundle *bundle = [NSBundle bundleWithPath:@"/Applications/Utilities/Keychain Access.app/Contents/Resources/Keychain.menu"];
    Class principalClass = [bundle principalClass];
    id instance = [[principalClass alloc] init];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    [instance performSelector:@selector(_lockScreenMenuHit:) withObject:nil];
#pragma clang diagnostic pop
}

- (void)quitAction:(NSMenuItem *)sender {
    [[NSApplication sharedApplication] terminate:nil];
}

#pragma mark - Property method

- (NSStatusItem *)statusItem {
    if (_statusItem == nil) {
        NSMenu *menu = [[NSMenu alloc] init];
        [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Start" action:@selector(switchAction:) keyEquivalent:@""]];
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quitAction:) keyEquivalent:@"q"]];
        NSStatusItem *statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
        statusItem.button.image = [NSImage imageNamed:@"Lock"];
        statusItem.menu = menu;
        _statusItem = statusItem;
        _switchMenuItem = menu.itemArray.firstObject;
    }
    return _statusItem;
}

- (NSMutableArray<GCDAsyncSocket *> *)pool {
    if (_pool == nil) {
        _pool = [NSMutableArray array];
    }
    return _pool;
}

- (void)setIsStart:(BOOL)isStart {
    _isStart = isStart;
    self.statusItem.menu.itemArray.firstObject.title = _isStart?@"Stop":@"Start";
}

@end
