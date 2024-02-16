#!/bin/bash

# ln -s {currentfile(setup.sh)} /usr/bin/labauto

echo -e "\n\e[1;33m You can find all the scripts in below repo.\e[0m\n"
echo -e "https://github.com/mrjithendar/tools.git\n"


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
  TOOL_NAME_FROM_NUMBER=$(ls -1 /tmp/tools/devops | cat -n | grep -w $tool | awk '{print $NF}')

  if [ ! -f /tmp/tools/devops/$tool.sh -a -z "${TOOL_NAME_FROM_NUMBER}" ]; then
    echo -e "\e[1;31m Given Tool Not Found \e[0m"
    exit 1
  fi
  tool=${TOOL_NAME_FROM_NUMBER}
else
  tool=$1
fi

SCRIPT_COUNT=$(ls /tmp/tools/devops/$tool | wc -l)
case $SCRIPT_COUNT in
  1)
    echo -e "\e[1;33m★★★ Installing $tool ★★★\e[0m"
    sh /tmp/tools/devops/$tool
    ;;
  *)
    echo -e "\e[31m Found Multiple Scripts, Choose One..\e[0m"
    select script in `ls -1 /tmp/tools/devops/$tool | awk -F / '{print $NF}'`; do
      echo -e "\e[1;33m★★★ Installing $tool ★★★\e[0m"
      sh /tmp/tools/devops/$tool
      break
    done
    ;;
esac
