# Owner 固定目标分支与误上传纠正授权

日期：2026-11-04。来源：当前Owner对话。

Owner原话：
> 是这样的，这个分支是另外一个人的分支，我希望我们永远不要动，我们上传到这个分支就可以https://github.com/AhakeyAI/desktop/tree/win-zxy-harness，如果之前有之前的过程中提交到anpx分支的，你看看能不能撤回，统一都提交到这个zxy的分支上

既有2026-10-27指派也明确指定win-zxy-harness。上一轮沿用main-anpx上传不符合目标分支要求，本轮纠正。

授权：先将Windows 1.0.19源码、相关Harness及原始候选历史完整保存至origin/win-zxy-harness；然后只撤回误上传至main-anpx的本项目增量。保留协作者原有及后续提交，不强推、不删除分支、不重写历史；采用可审计的回退提交恢复误上传前的文件内容。修改本项目AGENTS并设置本地推送保护，今后固定zxy目标。

已查证本地远端reflog：本次误上传之前main-anpx为22e49fbbc012ffc642b0d5a0da389dadf0c28e58，随后由本次两次push更新至7e8c2199和369da0d7。旧基线的Windows历史属于原协作者，不能因目录是Windows而一并撤回。当前远端仍为369da0d7，无后续他人提交。

win-zxy-harness现有基线bc633a75保留为第一父提交。Windows生产输入取已保存的1.0.19候选；目标分支其他平台和既有Harness历史保留。以受控合并保留369da0d7及其祖先，既有候选SHA不失效；不恢复WD007拒收实现，不构建、安装或发布。
