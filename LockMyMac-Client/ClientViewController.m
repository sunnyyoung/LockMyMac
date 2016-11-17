//
//  ClientViewController.m
//  LockMyMac
//
//  Created by Sunnyyoung on 2016/11/15.
//
//

#import "ClientViewController.h"

static NSString * const NetServiceDomain    = @"local.";
static NSString * const NetServiceType      = @"_LockMyMac._tcp.";

static dispatch_queue_t client_socket_queue() {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_queue_attr_t attr = DISPATCH_QUEUE_SERIAL;
        attr = dispatch_queue_attr_make_with_qos_class(attr, QOS_CLASS_BACKGROUND, 0);
        queue = dispatch_queue_create("net.sunnyyoung.LockMyMac-Client.socket", attr);
    });
    return queue;
}

@interface ClientViewController () <UITableViewDataSource, UITableViewDelegate, NSNetServiceBrowserDelegate, NSNetServiceDelegate, GCDAsyncSocketDelegate>

@property (nonatomic, strong) NSNetServiceBrowser *netBrowser;
@property (nonatomic, strong) GCDAsyncSocket *socket;
@property (nonatomic, strong) NSMutableArray<NSNetService *> *serviceArray;

@property (weak, nonatomic) IBOutlet UITableView *tableView;

@end

@implementation ClientViewController

#pragma mark - Lifecycle

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        _netBrowser = [[NSNetServiceBrowser alloc] init];
        _netBrowser.delegate = self;
        _socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:client_socket_queue()];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.netBrowser searchForServicesOfType:NetServiceType inDomain:NetServiceDomain];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.netBrowser stop];
}

#pragma mark - TableView DataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.serviceArray.count;
}

#pragma mark - TableView Delegate

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    NSNetService *service = self.serviceArray[indexPath.row];
    cell.textLabel.text = service.name;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"Port: %@", @(service.port).stringValue];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *addresses = self.serviceArray[indexPath.row].addresses;
    NSError *error = nil;
    for (NSUInteger index = 0; index < addresses.count; index++) {
        [self.socket connectToAddress:addresses[index] error:&error];
        if (!error) {
            [self.socket readDataWithTimeout:-1 tag:0];
            break;
        } else {
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Socket connect error" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [self presentViewController:alertController animated:YES completion:nil];
            continue;
        }
    }
}

#pragma mark - NetBrowser Delegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
    NSLog(@"DidFindService: %@", service.name);
    service.delegate = self;
    [service resolveWithTimeout:5.0];
    [self.serviceArray addObject:service];
    [self.tableView reloadData];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing {
    NSLog(@"DidRemoveService: %@", service.name);
    service.delegate = self;
    [service resolveWithTimeout:5.0];
    [self.serviceArray removeObject:service];
    [self.tableView reloadData];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didNotSearch:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    NSLog(@"DidNotSearch: %@", errorDict);
    [self.tableView reloadData];
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)browser {
    NSLog(@"DidStopSearch");
    [self.tableView reloadData];
}

- (void)netServiceDidResolveAddress:(NSNetService *)sender {
    NSLog(@"Resolved");
    [self.tableView reloadData];
}

#pragma mark - Socket Delegate

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    [sock readDataWithTimeout:-1 tag:0];
    [sock writeData:[@"LOCK\n" dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1 tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    [sock disconnect];
}

#pragma mark - Property method

- (NSMutableArray<NSNetService *> *)serviceArray {
    if (_serviceArray == nil) {
        _serviceArray = [NSMutableArray array];
    }
    return _serviceArray;
}

@end
