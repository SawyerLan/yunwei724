[TOC]

这是**使用ansible部署springboot系列** 的第二篇文章。

本系列文章介绍基于springboot的java程序如何自动化部署。该CI/CD方案基于Jenkins+Ansible，可以快速在企业落地。不了解Ansible或者Jenkins都没有关系，你甚至只需要复制方案代码并录入你的资产，即可落实该CI/CD方案了。



## 0 简单回顾
在 https://blog.csdn.net/sawyerlan/article/details/105326678 文中我们已经介绍了准备工作，以及环境资产的组织和包与主机的绑定，如果对此不是很明白，建议先阅读第一篇文章。

本篇文章主要介绍如何把程序做成系统托管的服务，告别以前使用shell脚本，使用rc.local 等做开机启动的模式。然后我们会讲解如何给程序指定启动的参数，比如有个jar包，在dev环境需要配置 Xmx=512M， 而在生产环境中需要配置Xmx=1G，本文将介绍如何解决：不同包的参数不同，不同包在不同环境的参数也不相同这些问题。



## 1 服务系统托管

### 1.1 为什么需要系统托管

读者可能纳闷： 这不是讲解ansible部署springboot系列文章吗？为什么这里需要讲解系统托管呢？

这是因为笔者希望提供一种**标准化的服务启停方案**，解决各种各样五花八门的启动脚本的问题。而系统托管的服务管理，也是ansible原生支持的，我们只需要告诉ansible我们的服务名，以及希望服务到达的状态，ansible会自动根据系统类型去解决服务的启停问题，

>  比如：我们不需要告诉ansible 在CentOS7下使用 systemctl start abc， 而在CentOS6下要使用 service start abc 这种启动方式，只需要告诉ansible，我需要**启动**一个服务，服务名是abc，ansible就会自己去分析该主机的操作系统，然后根据系统类型去选择启停方式。

我们要做的，就是把我们的服务，也就是你的jar包做成系统服务即可。那我们怎么做呢？ 

### 1.2 怎么实现服务的系统托管

**注： 笔者这里主要以CentOS系统举例**

使用linux的同学都知道，当我们使用yum安装软件时，比如使用yum安装redis，默认会帮我们创建好一个开机启动脚本。

* 在CentOS6下会创建 /etc/init.d/redis，cat  /etc/init.d/redis 可以看到该文件就是一个shell脚本，

* 在CentOS7下会创建 /usr/lib/systemd/system/redis.service，cat该文件可以看到/usr/lib/systemd/system/redis.service 这是一个配置文件，

内容比CentOS6下的redis启动脚本更优雅简洁。这是因为CentOS7使用了**systemd**取代了CentOS6的initd，这里我不做过多的介绍，感兴趣的可以访问

[Systemd 入门教程：命令篇 - 阮一峰的网络日志 (ruanyifeng.com)](http://www.ruanyifeng.com/blog/2016/03/systemd-tutorial-commands.html)

Systemd可以实现服务依赖，可以实现服务异常退出自动重启等等，CentOS7下使用systemd就可以了。

那CentOS6呢？像redis这样写一个启动脚本也是可以的，但笔者发现，还有一种方案也可以，而且比脚本更优雅，也是通过配置化的那就是upstart。

> 这是笔者在安装logstash时发现的，既然大名鼎鼎的logstash都可以用，那还是比较放心的。

![image-20201124160925117](C:\Users\hydee\AppData\Roaming\Typora\typora-user-images\image-20201124160925117.png)

配置文件内容如下

```bash
cat /etc/init/logstash.conf
description     "logstash"
start on filesystem or runlevel [2345]
stop on runlevel [!2345]

respawn
umask 022
nice 19
limit nofile 16384 16384
chroot /
chdir /

#limit core <softlimit> <hardlimit>

script
  # When loading default and sysconfig files, we use `set -a` to make
  # all variables automatically into environment variables.
  set -a
  [ -r "/etc/default/logstash" ] && . "/etc/default/logstash"
  [ -r "/etc/sysconfig/logstash" ] && . "/etc/sysconfig/logstash"
  set +a
  exec chroot --userspec logstash:logstash / /usr/share/logstash/bin/logstash "--path.settings" "/etc/logstash" >> /var/log/logstash-stdout.log 2>> /var/log/logstash-stderr.log
end script
```

关于upstart可以访问 [upstart把应用封装成系统服务 | 粉丝日志 (fens.me)](http://blog.fens.me/linux-upstart/) 进行学习

upstart托管的服务启动方式很简单，你可以通过以下命令就行管理：

* 列出服务 initctl list
* start/stop/restart 服务名 启停服务
* initctl reload-configuration 重新加载配置，如果配置文件变更了需要执行此命令才能生效。

那么我们只需要把我们的jar包服务的启动命令及启动参数，在CentOS7下做成systemd服务，在CentOS6下做成upstart服务即可。至于服务管理就可以完全交由ansible去管理了。那么ansible支持哪些服务托管类型呢？我们来看下官方文档。[service - Manage services — Ansible Documentation](https://docs.ansible.com/ansible/2.5/modules/service_module.html)

![image-20201124170349624](C:\Users\hydee\AppData\Roaming\Typora\typora-user-images\image-20201124170349624.png)

可以看到，ansible是完全支持upstart和systemd的。

接下来我们介绍如何把我们的jar包做成系统服务

### 1.3 把jar包服务做成系统托管

我们先看来下最终生成的效果文件

* CentOS7 下

```bash
[root@h3kf2 ~]# cat /usr/lib/systemd/system/h3-admin-server.service 
[Unit]
Description=hadmin-server
After=network.target

[Service]
WorkingDirectory=/usr/local/dubbo/
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=hadmin-server
LimitNOFILE = 65535
Type=simple
ExecStart=/usr/java/jdk1.8.0_181-amd64/jre/bin/java \
            -Dapollo.meta=http://192.168.10.131:9100 \
            -Xmx128M \
            -Xms128M \
            -Dfile.encoding=UTF-8 \
            -XX:CompressedClassSpaceSize=64M  \
            -XX:MaxMetaspaceSize=128M \
            -XX:MaxDirectMemorySize=64M \
            -XX:+HeapDumpOnOutOfMemoryError \
            -XX:HeapDumpPath=/data/jvm_dump/hadmin-server.heapdump \
            -XX:+UseG1GC \
            -XX:-OmitStackTraceInFastThrow \
            -Darthas.agent-id=hadmin-server_192.168.10.131 \
            -Darthas.tunnel-server=ws://arthas.example.cn/ws \
                                    -jar /usr/local/dubbo/hadmin-server.jar  --spring.profiles.active=dev              
ExecStop=/bin/kill -SIGTERM $MAINPID

[Install]
WantedBy=multi-user.target
```

我们可以看到这个jar包为  /usr/local/dubbo/hadmin-server.jar，启动参数有很多，比如：

* apollo的地址 -Dapollo.meta=http://192.168.10.131:9100
* jvm内存配置 -Xmx128M -Xms128M 
* 异常情况下jvm自动dump的文件路径 -XX:HeapDumpPath=/data/jvm_dump/h3-admin-server.heapdump 

这里的参数有很多，熟悉ansible的朋友很容易想到把这些参数的值做成变量即可，然后使用ansible的模板，在部署的时候ansible会自动替换模板变量。

那么我们来看看模板文件的样子：

```bash
cat roles/deploy_on_spring_boot/templates/yunwei724/service_spring_boot_systemd.j2
[Unit]
Description={{ item.split('/')[-1].split('.')[0] }}
After=network.target

[Service]
WorkingDirectory={{ host_spring_boot['path'] }}/
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier={{ item.split('/')[-1].split('.')[0] }}
LimitNOFILE = 65535
Restart=always
RestartSec=30
Type=simple
ExecStart={{ JAVA_HOME | regex_replace('/$','') }}/bin/java \
            -Dapollo.meta={{ apollo_addr }} \
            -Xmx{{ Xmx }} \
            -Xms{{ Xms }} \
            -Dfile.encoding=UTF-8 \
            -XX:CompressedClassSpaceSize={{ CompressedClassSpaceSize }}  \
            -XX:MaxMetaspaceSize={{ MaxMetaspaceSize }} \
            -XX:MaxDirectMemorySize={{ MaxDirectMemorySize }} \
            -XX:+HeapDumpOnOutOfMemoryError \
            -XX:HeapDumpPath={{ host_jvm_dump_dir }}/{{ item.split('/')[-1].split('.')[0] }}.heapdump \
            -XX:+UseG1GC \
            -XX:-OmitStackTraceInFastThrow \
            -Darthas.agent-id={{ item.split('/')[-1].split('.')[0] }}_{{ inventory_hostname }} \
            -Darthas.tunnel-server={{ tunnel_server }} \
            {% if sky_conf is defined %}
            {{ sky_conf }} \
            {% endif %}
            {% if enc_key is defined %}
            {{ enc_key }} \
            {% endif %}
            -jar {{ host_spring_boot['path'] }}/{{ item |basename }} {% if spring_profiles_active is defined %} --spring.profiles.active={{ spring_profiles_active }} {% endif %}
             
ExecStop=/bin/kill -SIGTERM $MAINPID

[Install]
WantedBy=multi-user.target
```

我们依次来看下该模板中的变量

* Description={{ item.split('/')[-1].split('.')[0] }}用来描述服务的信息。

   这个item需要关注下，item其实是ansible循环中的一个“项”，因为我们部署的时候，可能是勾选了多个jar包，故需要把勾选的多个包都遍历。在ansible 的task中大概如下：

  ```yaml
  - name: '配置systemd服务托管 CentOS7'
    template:
      src: "{{ lookup('vars', 'pkg7_'+item.split('/')[-1] |regex_replace('-','_')|regex_replace('\\.','_') )}}"
      dest: "/usr/lib/systemd/system/{{ item.split('/')[-1].split('.')[0] }}{{ service_tag | default('') }}.service"
    when: (host_spring_boot is defined and item.split('/')[-1] in host_spring_boot['pkgs']) and ansible_os_family == "RedHat" and ansible_distribution_major_version|int == 7
    loop: "{{ spring_boot['pkgs'] }}"
    notify: daemon-reload
  ```

  我们遍历了spring_boot['pkgs']这个变量，而item就是其中的一个项目。比如需要部署a.jar 和b.jar ，我们可以把spring_boot定义成

  ```yaml
  spring_boot:
    pkgs: 
      - a.jar 
      - b.jar
  ```

  在ansible遍历时，item就被替换为a.jar 或 b.jar了，我们还是用了一个split函数，为的是去掉后缀，生成像Description=hadmin-server 这样的描述信息。

* WorkingDirectory={{ host_spring_boot['path'] }}/ 定义工作目录

  这个变量定义在我的主机变量，如下：

  ```yaml
  cat inventories/yunwei724/host_vars/10.200.25.54.yml
  host_spring_boot:
    path: /data/app/middle
    pkgs:
      - a.jar
      - b.jar
  ```

  ![image-20201127232825640](C:\Users\hydee\AppData\Roaming\Typora\typora-user-images\image-20201127232825640.png)

  

* 日志配置

  StandardOutput=syslog
  StandardError=syslog
  SyslogIdentifier={{ item.split('/')[-1].split('.')[0] }}

  这三个配置都是日志输出重定向。因为通过systemd托管的服务，日志默认都会使用操作系统的journal记录，而我们需要把标准输出和标准错误输出都写到指定的文件。比如写到/data/app/logs/a.log里。

* ExecStart 这里指定程序启动的命令及参数

  * {{ JAVA_HOME | regex_replace('/$','') }}/bin/java 这里指定java的路径。通常我会在all.yml定义一个全局的JAVA_HOME变量

    ![image-20201127233459249](C:\Users\hydee\AppData\Roaming\Typora\typora-user-images\image-20201127233459249.png)

    如果你各个环境的配置都一样，那都可以定义在all.yml 文件中，但如果各个环境不同，你可以单独定义在环境变量文件中，如dev.yml。更有每个机器的配置不同，你当然也可以单独定义在10.200.12.1.yml 类似这样的主机变量文件中。
    
  * Dapollo.meta={{ apollo_addr }} 这里指定apollo的地址。

    ![image-20201127234030178](C:\Users\hydee\AppData\Roaming\Typora\typora-user-images\image-20201127234030178.png)

  余下的其他参数都是类似的，比如-Xmx{{ Xmx }}。

  * {% if sky_conf is defined %} 这个需要注意，因为有时候我们只要在特定环境加上参数，而有的环境不需要，比如笔者这里的skywalking的配置，我们在dev环境就不需要，而在pro环境就需要。我们这里用了jinjia2的语法做了判断，如果sky_conf 定义了就会进行渲染，没有定义自然就不会走这个逻辑了。

    ![image-20201127234522325](C:\Users\hydee\AppData\Roaming\Typora\typora-user-images\image-20201127234522325.png)

至此，该模板文件就介绍得差不多了。总结下：

* 我们需要把服务做成系统托管服务

* 我们定义了这样的一个模板

* 我们在组变量文件、主机变量文件等中定义好我们的变量，从而解决了各个环境配置不同的问题

  这里再给出2个组变量文件供参考分别是pro环境和test环境的

  ```yaml
  cat inventories\yunwei724\group_vars\pro.yml
  JAVA_HOME: /usr/local/jdk1.8.0_211
  apollo_addr: http://10.25.19.228:7100
  senti_addr: 172.30.0.112:8000
  Xmx: 2048M
  Xms: 512M
  CompressedClassSpaceSize: 128m
  MaxMetaspaceSize: 256M
  MaxDirectMemorySize: 256M
  
  cat inventories\yunwei724\group_vars\test.yml
  JAVA_HOME: /usr/local/jdk1.8.0_211
  apollo_addr: http://10.200.25.125:8100
  senti_addr: 10.200.25.142:8000
  Xmx: 512M
  Xms: 256M
  CompressedClassSpaceSize: 128m
  MaxMetaspaceSize: 256M
  MaxDirectMemorySize: 256M
  ```

  有的同学可能就会想，这样我的每个服务的在同一个环境或者是机器下，参数就都一样了，比如我的a.jar 和b.jar 如果都部署在test环境下，那他们的启动参数都将是Xmx: 512M Xms: 256M ，但是，我的b服务很耗内存，需要配置为Xmx: 2G怎么办呢？这就引出了一个新的东西：包模板和包变量，这个就到下个章节再讲解。

> 代码路径 https://github.com/SawyerLan/yunwei724