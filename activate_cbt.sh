#!/bin/bash
# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 激活虚拟环境
if [ -f "$SCRIPT_DIR/cbt_env/bin/activate" ]; then
    source "$SCRIPT_DIR/cbt_env/bin/activate"
    echo "CBT虚拟环境已激活！"
    echo "当前Python路径: $(which python)"
    echo "Python版本: $(python --version)"
else
    echo "错误: 找不到虚拟环境 $SCRIPT_DIR/cbt_env/bin/activate"
    exit 1
fi
