#!/bin/bash

# Nockchain挖矿管理脚本
# 版本: 1.0
# 日期: 2025-05-19
# 功能: 支持Nockchain挖矿全流程管理

# 配置变量
CONFIG_FILE="$HOME/.nockchain_miner.conf"
LOG_FILE="$HOME/nockchain_miner.log"
NOCKCHAIN_REPO="https://github.com/zorp-corp/nockchain.git"
NOCKCHAIN_DIR="$HOME/nockchain"
WALLET_DIR="$HOME/nockchain_wallets"

# 初始化配置
init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        mkdir -p "$WALLET_DIR"
        touch "$CONFIG_FILE"
        echo "WALLET_DIR=$WALLET_DIR" >> "$CONFIG_FILE"
        echo "MINING_ADDRESS=" >> "$CONFIG_FILE"
        echo "RPC_ENDPOINT=https://rpc.nockchain.org" >> "$CONFIG_FILE"
    fi
    source "$CONFIG_FILE"
}

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 安装依赖环境
install_dependencies() {
    log "开始安装系统依赖..."
    sudo apt-get update
    sudo apt-get install -y git build-essential cmake pkg-config libssl-dev libclang-dev clang llvm \
        libgmp-dev libsqlite3-dev zlib1g-dev npm nodejs python3-pip curl wget jq
    
    log "安装Rust工具链..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
    
    log "安装Node.js和npm..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
    
    log "安装Docker..."
    sudo apt-get install -y docker.io docker-compose
    sudo systemctl enable --now docker
    
    log "安装Solana工具链..."
    sh -c "$(curl -sSfL https://release.solana.com/v1.14.18/install)"
    
    log "依赖安装完成"
}

# 克隆并构建Nockchain
setup_nockchain() {
    log "克隆Nockchain仓库..."
    if [ -d "$NOCKCHAIN_DIR" ]; then
        log "检测到已存在的Nockchain目录，尝试更新..."
        cd "$NOCKCHAIN_DIR" && git pull
    else
        git clone "$NOCKCHAIN_REPO" "$NOCKCHAIN_DIR"
        cd "$NOCKCHAIN_DIR"
    fi
    
    log "构建Nockchain节点..."
    cargo build --release
    
    log "构建挖矿程序..."
    cd miner && npm install && cd ..
    
    log "Nockchain环境设置完成"
}

# 钱包管理
wallet_management() {
    echo "===== 钱包管理 ====="
    echo "1. 创建新钱包"
    echo "2. 导入现有钱包"
    echo "3. 列出所有钱包"
    echo "4. 查询钱包余额"
    echo "5. 返回主菜单"
    read -p "请选择操作: " wallet_choice
    
    case $wallet_choice in
        1)
            create_wallet
            ;;
        2)
            import_wallet
            ;;
        3)
            list_wallets
            ;;
        4)
            check_balance
            ;;
        5)
            return
            ;;
        *)
            echo "无效选择"
            ;;
    esac
}

# 创建新钱包
create_wallet() {
    read -p "输入钱包名称: " wallet_name
    wallet_path="$WALLET_DIR/$wallet_name"
    
    if [ -f "$wallet_path" ]; then
        log "钱包 $wallet_name 已存在"
        return
    fi
    
    log "创建新钱包 $wallet_name..."
    "$NOCKCHAIN_DIR/target/release/nockchain-wallet" create --outfile "$wallet_path"
    
    # 显示助记词和地址
    echo "===== 重要提示 ====="
    echo "请安全保存以下信息:"
    echo "钱包文件: $wallet_path"
    echo "助记词: $(jq -r '.mnemonic' "$wallet_path")"
    echo "地址: $(jq -r '.address' "$wallet_path")"
    echo "===================="
    
    read -p "是否将此钱包设为挖矿收款地址? (y/n): " set_mining
    if [[ "$set_mining" == "y" || "$set_mining" == "Y" ]]; then
        MINING_ADDRESS=$(jq -r '.address' "$wallet_path")
        sed -i "s/MINING_ADDRESS=.*/MINING_ADDRESS=$MINING_ADDRESS/" "$CONFIG_FILE"
        log "已将 $wallet_name ($MINING_ADDRESS) 设为挖矿地址"
    fi
}

# 导入钱包
import_wallet() {
    read -p "输入助记词 (用空格分隔): " mnemonic
    read -p "输入钱包名称: " wallet_name
    wallet_path="$WALLET_DIR/$wallet_name"
    
    if [ -f "$wallet_path" ]; then
        log "钱包 $wallet_name 已存在"
        return
    fi
    
    log "导入钱包 $wallet_name..."
    "$NOCKCHAIN_DIR/target/release/nockchain-wallet" import --mnemonic "$mnemonic" --outfile "$wallet_path"
    
    echo "导入成功!"
    echo "地址: $(jq -r '.address' "$wallet_path")"
    
    read -p "是否将此钱包设为挖矿收款地址? (y/n): " set_mining
    if [[ "$set_mining" == "y" || "$set_mining" == "Y" ]]; then
        MINING_ADDRESS=$(jq -r '.address' "$wallet_path")
        sed -i "s/MINING_ADDRESS=.*/MINING_ADDRESS=$MINING_ADDRESS/" "$CONFIG_FILE"
        log "已将 $wallet_name ($MINING_ADDRESS) 设为挖矿地址"
    fi
}

# 列出所有钱包
list_wallets() {
    echo "===== 钱包列表 ====="
    for wallet in "$WALLET_DIR"/*; do
        if [ -f "$wallet" ]; then
            echo "名称: $(basename "$wallet")"
            echo "地址: $(jq -r '.address' "$wallet")"
            echo "创建时间: $(jq -r '.created_at' "$wallet")"
            echo "------------------------"
        fi
    done
}

# 查询钱包余额
check_balance() {
    list_wallets
    read -p "输入要查询的钱包名称: " wallet_name
    wallet_path="$WALLET_DIR/$wallet_name"
    
    if [ ! -f "$wallet_path" ]; then
        log "钱包 $wallet_name 不存在"
        return
    fi
    
    address=$(jq -r '.address' "$wallet_path")
    balance=$("$NOCKCHAIN_DIR/target/release/nockchain-cli" get-balance --address "$address" --rpc "$RPC_ENDPOINT")
    
    echo "===== 钱包余额 ====="
    echo "地址: $address"
    echo "余额: $balance NOCK"
    echo "===================="
}

# 查询已挖出的币
check_mined_coins() {
    if [ -z "$MINING_ADDRESS" ]; then
        log "未设置挖矿地址，请先在钱包管理中设置"
        return
    fi
    
    log "查询挖矿收益..."
    mined_coins=$("$NOCKCHAIN_DIR/target/release/nockchain-cli" get-mining-rewards --address "$MINING_ADDRESS" --rpc "$RPC_ENDPOINT")
    
    echo "===== 挖矿收益 ====="
    echo "挖矿地址: $MINING_ADDRESS"
    echo "已挖出: $mined_coins NOCK"
    echo "待领取: $("$NOCKCHAIN_DIR/target/release/nockchain-cli" get-pending-rewards --address "$MINING_ADDRESS" --rpc "$RPC_ENDPOINT") NOCK"
    echo "===================="
}

# 启动挖矿
start_mining() {
    if [ -z "$MINING_ADDRESS" ]; then
        log "未设置挖矿地址，请先在钱包管理中设置"
        return
    fi
    
    if pgrep -f "nockchain-miner" > /dev/null; then
        log "挖矿程序已经在运行"
        return
    fi
    
    log "启动挖矿程序..."
    cd "$NOCKCHAIN_DIR/miner"
    nohup npm start -- --address "$MINING_ADDRESS" --rpc "$RPC_ENDPOINT" >> "$LOG_FILE" 2>&1 &
    
    log "挖矿已启动，日志输出到 $LOG_FILE"
}

# 停止挖矿
stop_mining() {
    if ! pgrep -f "nockchain-miner" > /dev/null; then
        log "没有运行的挖矿程序"
        return
    fi
    
    log "停止挖矿程序..."
    pkill -f "nockchain-miner"
    
    log "挖矿已停止"
}

# 重启挖矿
restart_mining() {
    stop_mining
    start_mining
}

# 查看挖矿日志
view_logs() {
    less "$LOG_FILE"
}

# 主菜单
main_menu() {
    init_config
    
    while true; do
        echo "===== Nockchain挖矿管理 ====="
        echo "1. 安装依赖环境"
        echo "2. 设置Nockchain环境"
        echo "3. 钱包管理"
        echo "4. 查询已挖出的币"
        echo "5. 启动挖矿"
        echo "6. 停止挖矿"
        echo "7. 重启挖矿"
        echo "8. 查看挖矿日志"
        echo "9. 退出"
        read -p "请选择操作: " choice
        
        case $choice in
            1)
                install_dependencies
                ;;
            2)
                setup_nockchain
                ;;
            3)
                wallet_management
                ;;
            4)
                check_mined_coins
                ;;
            5)
                start_mining
                ;;
            6)
                stop_mining
                ;;
            7)
                restart_mining
                ;;
            8)
                view_logs
                ;;
            9)
                log "退出脚本"
                exit 0
                ;;
            *)
                echo "无效选择"
                ;;
        esac
        
        echo ""
    done
}

# 启动主菜单
main_menu
