# v0.4 交付关口与命令
以下`H`代表 `.agents/skills/ahakey-desktop-harness/scripts/desktop.py`；命令中的`...`请替换完整脚本路径，不是字面可执行命令。role是协作声明，不是强身份认证。

## WD-001 在途升级：从实际差异审阅接续
无需重做实现、重开任务或重新批准现有合同。原start、change、Owner批准、references、submission、verification、execution report字节保留。升级新增guard-origin并备份当前源码；这份当前快照不冒充历史起点。
先 `python H guard-status --id WD-001`，再 `python H review-pack --id WD-001 --role DLA`。
若reference实际变化，说明受影响协议，不把结构检查失败和外部语义过期混同；必要时reopen受影响Contract，不能删引用凑PASS。
review-pack根据原始start计算累计变化，尝试从当前文件、保存副本和HEAD恢复旧字节。缺旧字节时可 `recover-start --id WD-001 --commit <原提交> --role DLA`，只恢复到私有evidence，不改产品或start。仍缺则明确限制；不得编造旧diff。必要时Owner明确接受有限历史缺口，记录baseline_gap_owner_record，但不能接受已发现的真实越界。

## 新任务
new按Owner指派建立DRAFT，填写已有Contract字段；源码/测试/资源起点需Git可恢复，`baseline-start --id <ID> --role DLA`记录原始指纹/本地内容备份；随后approve一次批准范围。没有已验证基线可标UNKNOWN并安排相关测试，不做全局重验。
若baseline-start返回GIT_SAVE_REQUIRED，DLA识别已有工作与本轮归属，给精确清单让Owner先存档，不能盲目git add -A或覆盖start。

## 真正的审阅
`review-pack`生成reviews/<stamp>/ACTUAL_DIFF.txt、PACK.json及REVIEW.json模板（已有模板不覆盖，只输出新表）。
DLA在REVIEW.json中填写：对应pack_sha256、独立DLA/Builder会话标识、每个文件目的与审阅hunks、真实运行链、旧行为/协议/基线风险、发现与处理。普通任务现有DLA审阅；high/fresh_review_required需独立新会话报告，记录当前pack指纹。
完成后：
`python H record-check --id WD-001 --check review --status pass --evidence .ahakey-desktop-harness/changes/WD-001/REVIEW.json --role DLA`
Markdown可另附；不能只附空模板。工具验证字段/绑定，不宣称人真的阅读或语义绝对正确。发现越界/阻塞就record fail/request-fix或reopen，不强行填写true。

## Git 候选
`python H candidate-plan --id WD-001 --role DLA`
输出CANDIDATE_GIT_PLAN.ps1：精确列本轮未提交输入与合同/审阅证据，只做暂存和展示、不commit。DLA先检查清单，Owner决定是否运行。索引已有暂存则计划停下，不自动reset。目录之外原有工作不带入。
Owner查看staged diff后自行commit（可以触发用户Git hooks），返回实际记录。然后：
`python H candidate-check --id WD-001 --commit HEAD --owner-record .ahakey-desktop-harness/evidence/<实际记录>.md --role DLA`
核对Git blob和当前输入及关键记录，允许仅UTF-8 CRLF/LF差异，其他内容/未知过滤器/LFS映射不能默许。检查不执行Git过滤器或hooks。candidate是待UAT，不自动发布。
升级后的未提交Harness治理文件可由Owner独立存档；它们不混作六个生产文件，不需伪装在allowed_paths内。候选计划不默认提交local.json、备份、runtime大产物或所有历史。

## 可运行构建
DIB可继续在相同任务内做已授权打包和机器验证，不因此获准重写代码。构建之前需查看脚本副作用和JDK/Maven实际runtime；JDK临时环境优先，不自动改系统配置。
`python H build-open --id WD-001 --role DIB`
记录打印token，执行核验后的实际构建（helper不执行），保存输出/退出码。然后例：
`python H build-finish --id WD-001 --token <打印token> --artifact target/<真实runtime目录> --log .ahakey-desktop-harness/evidence/<真实构建日志> --command "实际执行命令" --entrypoint "实际启动方法" --runtime-kind classes_classpath --role DIB`
artifact可多次指定，jar/classpath/executable均要列全相关runtime与依赖；目录递归manifest。token只能finish一次，输入变化需重开，不用旧compile.log伪装新build。收据绑定观察输入/日志/文件，不是可复现构建或能启动证明。
升级前只有compile的任务不能直接当可运行包；有旧产物而缺前置绑定时重新构建/打包，不要求重做实现。

## 真机交接
填写OWNER_TEST.md和OWNER_TEST.json（steps、expected、connection、恢复、写入副作用、刻意不变项）。设备任务用FIRMWARE_IDENTITY.json，填真实hardware/version/candidate与固件相对路径+SHA，gate_evidence需已允许测试的回执；installed_device_confirmation可写“待Owner核对已刷版本，未确认前不写设备”，不能猜已安装版本。
`python H request-test --id WD-001 --artifact .ahakey-desktop-harness/changes/WD-001/BUILD_RECEIPT.json --firmware-record .ahakey-desktop-harness/changes/WD-001/FIRMWARE_IDENTITY.json --role DLA`
也可--artifact传manifest中真实入口文件；不能传无关MD充当exe。DLA提供完整命令，不机械照抄示例占位符。
Owner真实反馈后record-check --check real_device/owner_uat pass或fail，绑定当前packet。不代测试、不代刷机。只读结构PASS不说明HEX、UI或UAT通过。

## 失败、暂停与收口
所有变更、检查、候选、测试交接前后追加history快照，保留相关证据字节。日志用新文件名，不覆盖既有fail。request-fix提高轮次，旧审阅/UAT不再对新代码生效。reopen只改受影响语义。
暂停前可用`savepoint-plan --id WD-001 --role DLA`生成仅供Owner审核的debug存档计划（不要求伪造审阅通过）。suspend需当前源码有可恢复提交；这是debug保存，不需要假review/pass。resume不重置原始start。并列平台新工作触发警告，DLA分类并经Owner确认可用`reconcile-foreign --id ... --owner-record ... --role DLA`登记，不还原别人代码。
通过后archive-plan生成关键合同/审阅/构建身份/Owner结果列表，Owner检查并提交；archive-check核对实际commit；close。close产生的状态与索引属于bookkeeping，可下一批保存，不导致commit回执无限循环。必要结果缺存档要提前说清。

## 安全与能力限度
helper是协作核验，不是沙箱/身份认证；角色参数、JSON中的PASS、Owner引述均需真实来源。无法证明审阅质量、日志真实性、构建可复现性或权限没有被外部程序绕过。source fingerprint继承v0.3排除列表，治理文件有独立seal，并列文件覆盖已声明；不意味着整个磁盘都被监控。签名seal可由有写权限的人改动，因此不是对抗恶意篡改的证明。
