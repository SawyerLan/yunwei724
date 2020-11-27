#!/bin/bash

# ansible-playbook -i inventories/hydee/hosts playbooks/deploy_on_spring_boot.yml -e @playbooks/test.yml

ANSIBLE_HOME=/data/ansible_data/
ANSIBLE_INV_HOME=$ANSIBLE_HOME/inventories
PALYBOOK_HOME=$ANSIBLE_HOME/playbooks


PROJECT=yunwei724
deploy_type=deploy_on_spring_boot


params_file=/tmp/$(uuidgen)
ansible_result=/tmp/ansible-$(uuidgen)

# 动态生成jar包
jar_list=''
for i in $jar_name
do
    #jar_list=$(echo $jar_list "'$WORKSPACE/$i/target/$i.jar',")
    jar_list=$(echo $jar_list "'$WORKSPACE/target/$i.jar',")
done
a=$(echo $jar_list |sed 's/,$//')
jar_list="[$a]"

cat > $params_file <<EOF
---
project_env: ${env}
deploy_type: $deploy_type
pkg: $jar_list
env_password: ${env_password}
EOF
echo "本次部署的参数---------- >>>>>>>>>>>>"
echo git分支${hydee_git_branch}

cat $params_file |grep -v password
echo "本次部署的参数---------- <<<<<<<<<<<<"

/usr/local/python3/bin/ansible-playbook -i $ANSIBLE_INV_HOME/$PROJECT/hosts \
                         $PALYBOOK_HOME/deploy_on_spring_boot.yml \
                         --vault-id=/data/ansible_data/ansible_pwd \
                         -e @${params_file} 2>&1 | tee $ansible_result

failed=$(cat $ansible_result |awk 'n==1{print} $0~/PLAY RECAP/{n=1}'  |grep -v ^$ |grep -oP 'failed=\d+' |awk -F'=' '{print $2}' |awk '{sum+=$1}END{print sum}')
changed=$(cat $ansible_result |awk 'n==1{print} $0~/PLAY RECAP/{n=1}' |grep -v ^$ |grep -oP 'changed=\d+' |awk -F'=' '{print $2}' |awk '{sum+=$1}END{print sum}')
unreachable=$(cat $ansible_result |awk 'n==1{print} $0~/PLAY RECAP/{n=1}' |grep -v ^$ |grep -oP 'unreachable=\d+' |awk -F'=' '{print $2}' |awk '{sum+=$1}END{print sum}')

if [ $failed != 0 ] || [ $changed = 0 ] || [ $unreachable != 0 ] ;then
    echo "部署失败"  && exit 1
else
    echo "部署成功"  && exit 0
fi



rm -vf /tmp/$params_file