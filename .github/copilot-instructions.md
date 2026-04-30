# Copilot Rules

- 每次构建完成后，必须生成 DMG 文件。
- 构建统一使用 `bash Scripts/build.sh`，该脚本已内置构建后自动执行 `bash Scripts/create-dmg.sh` 的打包钩子（除非显式设置 `SKIP_DMG=1`）。
