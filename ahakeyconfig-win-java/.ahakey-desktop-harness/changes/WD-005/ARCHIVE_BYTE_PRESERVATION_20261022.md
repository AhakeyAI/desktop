# WD-005 原始证据Git字节保真补充

日期：2026-10-22。仍为Owner已授权74项记录内操作，未增加路径或修改原件。

首次归档提交211a95e2acb89246687ee2ce69b3907bfd531873后，正式archive-check退出1：CanvasPane.current.javap.txt提交内容不等价。进一步逐项定位4份CanvasPane.*javap.txt均含非UTF-8原始输出，Git默认autocrlf将CRLF转LF；原文件未变。先前DLA自查只校验原字节或换行一致，未同时限制UTF-8，不能代替Harness更严格规则。没有将失败当作PASS。

Harness equivalent只对有效UTF-8接受CRLF/LF等价，这一规则保持不变。原始输出（包括文件名含utf8的副本）保持实际字节，不通过转码、改名、修改hash或改规则绕过。

对这4个原授权路径执行一次性git -c core.autocrlf=false add --renormalize，未改持久Git配置、规则、索引中其他文件或工作区原件。暂存4文件全部与原件字节相同；全部74文件按Harness同样的原字节/仅有效UTF-8换行规则重新核对通过；git diff --cached --ignore-space-at-eol --exit-code为0，证明仅换行变化。

新建保真提交8c654c99a582d897d50698148e6c83cbe51c5d59，父提交211a95e2acb89246687ee2ce69b3907bfd531873；退出0。未amend或重写历史，未push。源码候选仍e08524cc07077a06d34b79130ddea074355ea2fb。

原47份归档与此4份字节保真修正累计均不超出74项授权，产品/桥接/固件/本机配置未进入提交。已重新运行正式archive-check，结果以正式archive_receipt为准，本文不预先宣称关闭。
