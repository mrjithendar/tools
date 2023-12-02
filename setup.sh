#!/bin/bash

echo -e "\n\e[1;33m You can find all the scripts in following location\e[0m\nhttps://github.com/mrjithendar/tools/tree/master/tools\n"

#source `dirname $0`/dry/common-functions.sh

if [ ! -d /tmp/tools  ]; then 
	git clone https://github.com/mrjithendar/tools.git /tmp/tools &>/dev/null
else 
	cd /tmp/tools
	git stash &>/dev/null
	git pull &>/dev/null
fi

if [ -z "$1" ]; then
  echo -e "${Y}>>>>> Select a TOOL to Install${N}"
  bash /tmp/tools/menu
  echo -e "💡\e[1m You can choose number or tool name\e[0m"
  read -p 'Select Tool> ' tool
  TOOL_NAME_FROM_NUMBER=$(ls -1 /tmp/tools/tools | cat -n | grep -w $tool | awk '{print $NF}')

  if [ ! -f /tmp/tools/tools/$tool/install.sh -a -z "${TOOL_NAME_FROM_NUMBER}" ]; then
    echo -e "\e[1;31m Given Tool Not Found \e[0m"
    exit 1
  fi
  tool=${TOOL_NAME_FROM_NUMBER}
else
  tool=$1
fi

SCRIPT_COUNT=$(ls /tmp/tools/tools/$tool/*.sh |wc -l)
case $SCRIPT_COUNT in
  1)
    echo -e "\e[1;33m★★★ Installing $tool ★★★\e[0m"
    sh /tmp/tools/tools/$tool/install.sh
    ;;
  *)
    echo -e "\e[31m Found Multiple Scripts, Choose One.. "
    select script in `ls -1 /tmp/tools/tools/$tool/*.sh | awk -F / '{print $NF}'`; do
      echo -e "\e[1;33m★★★ Installing $tool ★★★\e[0m"
      sh /tmp/tools/tools/$tool/$script
      break
    done
    ;;
esac
