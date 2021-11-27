#!/usr/bin/env bash
set -eu

# 以下的变量，请按自己的需求修改
# 格式：变量名=值。等号两边不能有空格
LEVEL_NAME='server01'             # 世界存档文件夹的名字(别用中文比较好)
SERVER_NAME='My Server'           # 服务器名字，会显示在游戏里的列表上(中文OK)
SERVER_DIR="$HOME/server"         # "服务端"的位置
BACKUP_DIR="$HOME/backup"         # "备份文件夹"的位置
LOG_DIR="$BACKUP_DIR/log"         # "log文件夹"的位置
MAX_BACKUP=10                     # 备份存档的上限
STOP_WAIT_TIME=30                 # 关闭服务器时，等待玩家退出的时间。单位秒

# 以下的变量，无特别需求不用改
ESC=$(printf "\033")    # 更改输出颜色用的前缀/后缀
SESSION='mcServer'      # tmux的session名字


function color_print() {
    if [[ $# < 2 ]]; then
        echo "${ESC}[91m[Error] Wrong number of parameters.${ESC}[m"
        exit 1;
    fi

    case $1 in
    'info')
        echo "${ESC}[92m[Info] ${@:2}${ESC}[m"
    ;;
    'error')
        echo "${ESC}[91m[Error] ${@:2}${ESC}[m"
    ;;
    *)
        echo "${ESC}[$1m${@:2}${ESC}[m"
    ;;
    esac
}

function wait_for_action() {
    color_print $1 $2
    read
}

function main_panel() {
    fn_setup
    while true; do
        clear
        color_print 92 '========== ========== 欢迎使用服务端管理脚本 ========== =========='
        color_print 92 '此脚本仅限基岩版官方BDS使用'
        color_print 92 '作者是夜尘tide@百度贴吧'
        color_print 92 '========== ========== ====================== ========== =========='
        
        option_list=('启动服务器' '关闭服务器' '重启服务器' '查看log' '玩家登陆记录' '更新世界设置' '备份存档' '更新服务器')
        tip=$(color_print 93 '[退出或中断操作请直接按Ctrl+C]')
        PS3="${tip}"$'\n'"请输入选项代号："
        select option in ${option_list[*]}; do break; done
        
        case $option in
        '启动服务器')
            # test done!
            fn_start_server
            ;;
        '关闭服务器')
            # test done!
            fn_stop_server '即将关闭服务器，' $STOP_WAIT_TIME
            ;;
        '重启服务器')
            # test done!
            fn_stop_server '即将重启服务器，' $STOP_WAIT_TIME 'noaction'
            fn_start_server
            ;;
        '查看log')
            # test done!
            fn_show_current_log
            ;;
        '玩家登陆记录')
            # test done!
            fn_show_connection_history
            ;;
        '更新世界设置')
            fn_update_gamerule 'default'
            ;;
        '备份存档')
            fn_stop_server '即将备份世界存档，' $STOP_WAIT_TIME 'noaction'
            fn_backup
            fn_start_server
            ;;
        '更新服务器')
            fn_stop_server '即将更新服务器，' $STOP_WAIT_TIME 'noaction'
            fn_backup
            fn_update_bds
            fn_start_server
            ;;
        *)
            color_print error "${option}功能暂未写好"
            exit 1
            ;;
        esac
    done
}

function fn_setup() {
    requires=(tmux ts zip unzip)
    for package in ${requires[*]}; do
        if [[ $(which $package | wc -l) == 1 ]]; then
            echo "${package} is ok"
            continue
        fi
        if [[ $(whoami) != 'root' && $(groups $(whoami) | grep sudo | wc -l ) == 0 ]]; then
            color_print error "找不到软件$package, 并且当前用户$(whoami)没有权限安装软件包"
            exit 1
        fi
        
        if [[ $package == 'ts' ]]; then
            sudo apt install -y moreutils > /dev/null 2>&1
            continue
        fi
        sudo apt install -y $package > /dev/null 2>&1
    done

    if [[ -e $SERVER_DIR/bedrock_server && -e $BACKUP_DIR && -e $LOG_DIR ]]; then return; fi

    if [[ ! -e $SERVER_DIR/bedrock_server ]]; then
        color_print info "新建$SERVER_DIR文件夹，并下载服务端程序..."
        mkdir -p $SERVER_DIR;
        lastest_version=$(fn_get_lastest_bds_version)
        fn_install_bds $lastest_version
    fi
    if [[ ! -e $BACKUP_DIR ]]; then
        color_print info "新建$BACKUP_DIR文件夹"
        mkdir -p $BACKUP_DIR
    fi
    if [[ ! -e $LOG_DIR ]]; then
        color_print info "新建$LOG_DIR文件夹"
        mkdir -p $LOG_DIR
    fi
    wait_for_action info '输入回车继续'
}

function fn_check_server_process() {
    ps ua | grep $(whoami) | grep bedrock_server | grep -v grep | wc -l
}

function fn_start_server() {
    if [[ $(fn_check_server_process) > 0 ]]; then wait_for_action error '服务器已在运行，输入回车继续...'; return; fi
    if [[ $(tmux has-session -t $SESSION |& wc -l) == 0 ]]; then
        color_print info "重启tmux的 $SESSION session ..."
        fn_stop_server '即将重启服务器，' $STOP_WAIT_TIME
    fi
    
    tmux new -s $SESSION -d
    tmux pipe-pane -o "cat >> $LOG_DIR/#S_$(date "+%Y%m%d").log" \; display-message 'Logging start'

    sleepenh 0.5 > /dev/null 2>&1
    tmux send-keys -t $SESSION ENTER
    tmux send-keys -t $SESSION 'ESC=$(printf "\033"); cd ' $SERVER_DIR ' && LD_LIBRARY_PATH=. ./bedrock_server | ts "${ESC}[32m[%Y-%m-%d %H:%M:%S]${ESC}[m"' ENTER
    sleepenh 0.5 > /dev/null 2>&1
    color_print info '服务器已经开启!'

    if [[ $(fn_check_server_process) == 0 ]]; then wait_for_action error '服务器启动失败，输入回车结束...'; exit 1; fi
    if [[ $# == 1 && $1 == 'noaction' ]]; then return; fi
    
    wait_for_action info '输入回车继续'
}

function fn_count_current_log_lines() {
    echo $(cat $LOG_DIR/$(ls -rt $LOG_DIR | tail -n 1) | wc -l)
}

function fn_command_input() {
    if [[ $1 == 'hide' ]]; then
        tmux send-keys -t $SESSION "${@:2}" ENTER
    else
        old_log_lines=$(fn_count_current_log_lines)
        tmux send-keys -t $SESSION "$*" ENTER
        sleepenh 1 > /dev/null 2>&1
        new_log_lines=$(fn_count_current_log_lines)

        tail -n $(($new_log_lines-$old_log_lines-1)) $LOG_DIR/$(ls -rt $LOG_DIR | tail -n 1)
    fi
}
# result=$(fn_command_input $*)
# echo "$result"

function fn_anybody_online() {
    result=$(fn_command_input list)
    # echo "$result"
    if [[ $result =~ are.0\/[0-9]+.players ]]; then
        echo 1 # nobody online
    else
        echo 0 # somebody online
    fi
}

function fn_stop_server() {
    # if [[ $(fn_check_server_process) == 0 ]]; then wait_for_action error '未找到运行中的服务器，输入回车继续 ...'; return; fi
    if [[ $(tmux has-session -t $SESSION |& wc -l) > 0 ]]; then
        if [[ $# == 3 && $3 == 'noaction' ]]; then
            color_print error "未找到tmux的 $SESSION session ..."
        else
            wait_for_action error "未找到tmux的 $SESSION session, 输入回车继续 ..."
        fi
        return
    fi
    
    color_print info '正在关闭服务器 ...'
    if [[ $(fn_anybody_online) == 0 ]]; then
        color_print info "检测到有玩家在线，等待${STOP_WAIT_TIME}秒后关闭服务器 ..."
        sleepenh 0.5 > /dev/null 2>&1
        fn_command_input hide "say §l§c$1请在$2秒之内下线!!!"
        sleepenh 1 > /dev/null 2>&1
        for i in $(seq $2 -1 1); do
            fn_command_input hide "say §l§c$i"
            sleepenh 1 > /dev/null 2>&1
        done
        fn_command_input hide "say §l§c服务器即将关闭!!!"
    fi

    tmux pipe-pane \; display-message 'Logging end'
    tmux send-keys -t $SESSION C-c
    tmux kill-session -t $SESSION
    sleepenh 1.5 > /dev/null 2>&1

    if [[ $# == 3 && $3 == 'noaction' ]]; then return; fi
    wait_for_action info '服务器已关闭！输入回车继续 ...'
}

function fn_show_current_log() {
    #cat $LOG_DIR/$(ls -rt $LOG_DIR | tail -n 1) | grep -v Auto
    color_print info '============================='
    color_print info '退出或中断操作请直接按Ctrl+C'
    color_print info '============================='
    tail -f -n 20 $LOG_DIR/$(ls -rt $LOG_DIR | tail -n 1)
}

function fn_show_connection_history() {
    echo
    color_print info '===以下为登录过的玩家列表==='
    PS3=$(color_print 93 '(输入任意字符查看完整记录)'$'\n''请选择要查看的玩家: ')
    select player in $(grep Player $LOG_DIR/*.log | awk '{print substr($6, 1, length($6)-1)}' | sort | uniq); do break; done

    if [[ $player == '' ]]; then
	grep 'Player' $LOG_DIR/*.log | awk '{printf "%s %s %13s %s\n", substr($1, index($1, ":")+1), $2, $5, substr($6, 1, length($6)-1)}'
    else
        grep 'Player' $LOG_DIR/*.log | grep $player | awk '{printf "%s %s %13s %s\n", substr($1, index($1, ":")+1), $2, $5, substr($6, 1, length($6)-1)}'
    fi

    color_print info '输入回车退出'
    read
}

function fn_update_gamerule() {
    if [[ $# == 0 || $(fn_check_server_process) == 0 ]]; then
        wait_for_action error '未找到运行中的服务器进程bedrock_server，输入回车继续 ...'
    fi

    if [[ $1 == 'default' ]]; then
        tmux send-keys -t $SESSION "gamerule showCoordinates true" ENTER
        sleepenh 0.1 > /dev/null 2>&1
        tmux send-keys -t $SESSION "gamerule pvp false" ENTER
        sleepenh 0.1 > /dev/null 2>&1
        tmux send-keys -t $SESSION "gamerule tntExplodes false" ENTER
    else
        command="gamerule $@"
        tmux send-keys -t $SESSION "$command" ENTER
    fi

    echo 'update done!'
}

function fn_backup() {
    if [[ ! -e $SERVER_DIR/server.properties ]]; then echo "未找到文件$SERVER_DIR/server.properties"; return; fi
    if [[ ! -e $SERVER_DIR/worlds/$LEVEL_NAME ]]; then echo "未找到文件夹$SERVER_DIR/worlds/$LEVEL_NAME"; return; fi
    if [[ ! -e $BACKUP_DIR ]]; then echo "未找到文件夹$BACKUP_DIR"; return; fi

    cp $SERVER_DIR/server.properties $BACKUP_DIR/
    cp $SERVER_DIR/*.json $BACKUP_DIR/
    cp -r $SERVER_DIR/worlds/$LEVEL_NAME $BACKUP_DIR/$(date +"%Y_%m%d_%H%M")
    color_print info '备份完成！'
    # TODO: 追加・削除するディレクトリ名の表示

    if [[ $(ls -l $BACKUP_DIR | awk '$1 ~ /d/ {print $9 }' | wc -l) -gt $MAX_BACKUP ]]; then
        color_print info "备份数量超过设定的${MAX_BACKUP}，删除最旧的备份..."
        rm -rf $BACKUP_DIR/$(ls -lr $BACKUP_DIR | awk '$1 ~ /d/ {print $9 }' | tail -n 1)
        # TODO: 再帰的に削除
    fi
    sleepenh 1.5 > /dev/null 2>&1
}

function fn_check_current_bds_version() {
    if [[ ! -e $SERVER_DIR ]]; then echo "未找到文件夹$SERVER_DIR"; exit 1; fi
    echo $(ls ${SERVER_DIR}/bedrock-server*.zip | awk 'match($0, /bedrock-server-(.+)\.zip/, group){print group[1]}')
}

function fn_get_lastest_bds_version() {
    url='https://minecraft.fandom.com/zh/wiki/%E5%9F%BA%E5%B2%A9%E7%89%88%E4%B8%93%E7%94%A8%E6%9C%8D%E5%8A%A1%E5%99%A8'
    echo $(curl -s $url | grep '<th rowspan="1" colspan="5">' | grep 'title="基岩版' | tail -n 1 | awk 'match($0, /title.+>(.+)<\/a><\/th>/, group){print group[1]}')
}

function fn_install_bds() {
    color_print info "服务端最新版本为$1，即将开始下载..."
    bds_file="bedrock-server-$1.zip"

    rm -rf /tmp/bds
    mkdir /tmp/bds

    curl -o /tmp/bds/$bds_file "https://minecraft.azureedge.net/bin-linux/$bds_file"
    unzip -q /tmp/bds/$bds_file -d /tmp/bds
    chmod u+x /tmp/bds/bedrock_server

    if [[ -e $SERVER_DIR/bedrock_server && -e $SERVER_DIR/worlds/$LEVEL_NAME ]]; then
        mv $SERVER_DIR/server.properties /tmp/bds
        mv $SERVER_DIR/*.json /tmp/bds
        mv $SERVER_DIR/worlds /tmp/bds
        rm -rf $SERVER_DIR/*
    fi

    mv /tmp/bds/* $SERVER_DIR
    rm -rf /tmp/bds
    color_print info "$1服务端下载完成！"
}

function fn_update_bds() {
    current_version=$(fn_check_current_bds_version)
    lastest_version=$(fn_get_lastest_bds_version)
    if [[ $current_version == $lastest_version ]]; then
        color_print info '服务器已经是最新版本'
        return
    fi

    fn_install_bds $lastest_version
}

# function fn_auto_backup() {}

if [[ $# == 1 ]]; then
    case $1 in
    'update')
        fn_stop_server '即将更新服务器，' $STOP_WAIT_TIME 'noaction'
        fn_backup
        fn_update_bds
        fn_start_server 'noaction'
        ;;
    'backup')
        fn_stop_server '即将备份世界存档，' $STOP_WAIT_TIME 'noaction'
        fn_backup
        fn_start_server 'noaction'
        ;;
    'start')
        fn_start_server 'noaction'
        ;;
    'stop')
        fn_stop_server '即将关闭服务器，' $STOP_WAIT_TIME 'noaction'
        ;;
    *)
        color_print error '未知参数'
        exit 1
        ;;
    esac
    exit 0
fi

main_panel
