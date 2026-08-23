#ifndef AHAKEY_CLIBXPC_H
#define AHAKEY_CLIBXPC_H

#include <dispatch/dispatch.h>
#include <unistd.h>
#include <xpc/xpc.h>

/// macOS 12+ peer 签名校验包装：在 accepted connection 处理任何业务消息前调用。
/// 返回 0 表示 requirement 已设置；非 0 表示 libxpc 返回了错误对象。
int ahk_xpc_bind_peer_code_signing_requirement(xpc_connection_t connection,
                                               const char *requirement);

/// 创建 anonymous listener（name 为 NULL 的 mach service listener）。
xpc_connection_t ahk_xpc_create_anonymous_listener(dispatch_queue_t queue);

/// 创建当前用户域 Mach service listener。
xpc_connection_t ahk_xpc_create_mach_service_listener(const char *name,
                                                      dispatch_queue_t queue);

#endif /* AHAKEY_CLIBXPC_H */
