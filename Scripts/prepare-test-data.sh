#!/bin/bash
set -euo pipefail

BASE_DIR="${1:-$HOME/Desktop/Menu3-Test}"
SRC_DIR="$BASE_DIR/ClipboardSource"
DST_DIR="$BASE_DIR/TargetFolder"

rm -rf "$BASE_DIR"
mkdir -p "$SRC_DIR/SubFolder" "$DST_DIR"

printf "hello menu3\n" > "$SRC_DIR/a.txt"
printf "same name file\n" > "$SRC_DIR/未命名.txt"
printf "binary-demo\n" > "$SRC_DIR/sample.bin"
printf "nested file\n" > "$SRC_DIR/SubFolder/nested.txt"
touch "$SRC_DIR/noext"

printf "existing in target\n" > "$DST_DIR/未命名.txt"
printf "existing noext in target\n" > "$DST_DIR/noext"

echo "测试目录已创建：$BASE_DIR"
echo "源文件目录：$SRC_DIR"
echo "目标目录：$DST_DIR"
echo ""
echo "建议下一步："
echo "1) 在 Finder 打开：$DST_DIR"
echo "2) 复制源文件：open \"$SRC_DIR\" 后 Cmd+A / Cmd+C"
echo "3) 在目标目录空白处触发菜单测试\"保存文件 来自粘贴板\""
echo "4) 用 pbcopy 准备文本：echo '粘贴板文本测试' | pbcopy"
echo "5) 在目标目录空白处触发菜单测试\"保存成文本文件\""
