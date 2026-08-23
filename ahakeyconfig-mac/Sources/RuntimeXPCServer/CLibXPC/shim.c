#include "CLibXPC.h"

int ahk_xpc_bind_peer_code_signing_requirement(xpc_connection_t connection,
                                               const char *requirement) {
    // 返回 0 表示成功绑定；非 0 表示 requirement 无法解析/设置。
    return xpc_connection_set_peer_code_signing_requirement(connection, requirement);
}

xpc_connection_t ahk_xpc_create_anonymous_listener(dispatch_queue_t queue) {
    // 匿名 listener 由 xpc_connection_create(NULL, queue) 创建（见 xpc/connection.h）。
    return xpc_connection_create(NULL, queue);
}

xpc_connection_t ahk_xpc_create_mach_service_listener(const char *name,
                                                      dispatch_queue_t queue) {
    return xpc_connection_create_mach_service(name, queue, XPC_CONNECTION_MACH_SERVICE_LISTENER);
}
