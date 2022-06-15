[toc]

Guide based on: https://typhoon.psdn.io/flatcar-linux/bare-metal/

**Do not use .local as domain, because this has some wired issues because of mdns**

**Provisioned flatcar images still need a DHCP/DNS server!**

## Working principle
- matchbox service will provide relevant file during ipxe boot
- dnsmasq will be the ipxe server
- terraform will dynamically provision matchbox service based on the hcl configuration
- virtual machine (with specified MAC) will boot and will start the bootstrap

## HowTo
### create pool
```
(py310) peter@peter-desktop-2022:~$ virsh pool-list --all
 Name         State      Autostart
------------------------------------
 default      active     yes
 pool         active     yes
 pool-virsh   inactive   no
 uvtool       active     yes


(py310) peter@peter-desktop-2022:~$ virsh pool-build pool-virsh
Pool pool-virsh built

(py310) peter@peter-desktop-2022:~$ virsh pool-list --all
 Name         State      Autostart
------------------------------------
 default      active     yes
 pool         active     yes
 pool-virsh   inactive   no
 uvtool       active     yes

(py310) peter@peter-desktop-2022:~$ virsh pool-start pool-virsh
Pool pool-virsh started

(py310) peter@peter-desktop-2022:~$ virsh pool-list 
 Name         State    Autostart
----------------------------------
 default      active   yes
 pool         active   yes
 pool-virsh   active   no
 uvtool       active   yes

(py310) peter@peter-desktop-2022:~$ virsh pool-autostart pool-virsh
Pool pool-virsh marked as autostarted

(py310) peter@peter-desktop-2022:~$ virsh pool-list 
 Name         State    Autostart
----------------------------------
 default      active   yes
 pool         active   yes
 pool-virsh   active   yes
 uvtool       active   yes
```

### create vms
```
VM_MEMORY=2048
VM_DISK=30
VM_VCPUS=2
NODE1_NAME=node01
NODE2_NAME=node02
NODE3_NAME=node03
NODE1_MAC=$(hexdump -n3 -e'/3 "52:54:00" 3/1 ":%02x"' /dev/random)
NODE2_MAC=$(hexdump -n3 -e'/3 "52:54:00" 3/1 ":%02x"' /dev/random)
NODE3_MAC=$(hexdump -n3 -e'/3 "52:54:00" 3/1 ":%02x"' /dev/random)

echo node1 mac $NODE1_MAC
echo node2 mac $NODE2_MAC
echo node3 mac $NODE3_MAC

COMMON_VIRT_OPTS="--memory=${VM_MEMORY} --vcpus=${VM_VCPUS} --disk pool=pool-virsh,size=${VM_DISK} --os-type=linux --os-variant=generic --noautoconsole --events on_poweroff=preserve"

virt-install --name $NODE1_NAME --network=bridge:docker0,mac=$NODE1_MAC $COMMON_VIRT_OPTS --boot=hd,network
virt-install --name $NODE2_NAME --network=bridge:docker0,mac=$NODE2_MAC $COMMON_VIRT_OPTS --boot=hd,network
virt-install --name $NODE3_NAME --network=bridge:docker0,mac=$NODE3_MAC $COMMON_VIRT_OPTS --boot=hd,network
```

```
(py310) peter@peter-desktop-2022:~$ virt-install --name $NODE1_NAME --network=bridge:docker0,mac=$NODE1_MAC $COMMON_VIRT_OPTS --boot=hd,network
twork=bridge:docker0,mac=$NODE2_MAC $COMMON_VIRT_OPTS --boot=hd,network
virt-install --name $NODE3_NAME --network=bridge:docker0,mac=$NODE3_MAC $COMMON_VIRT_OPTS --boot=hd,network
Starting install...
Allocating 'node01.qcow2'                                                                                                                                                                     |  30 GB  00:00:10     
Domain creation completed.
(py310) peter@peter-desktop-2022:~$ virt-install --name $NODE2_NAME --network=bridge:docker0,mac=$NODE2_MAC $COMMON_VIRT_OPTS --boot=hd,network

Starting install...
Allocating 'node02.qcow2'                                                                                                                                                                     |  30 GB  00:00:11     
Domain creation completed.
(py310) peter@peter-desktop-2022:~$ virt-install --name $NODE3_NAME --network=bridge:docker0,mac=$NODE3_MAC $COMMON_VIRT_OPTS --boot=hd,network

Starting install...
Allocating 'node03.qcow2'                                                                                                                                                                     |  30 GB  00:00:11     
Domain creation completed.
```

### create DNSmasq config and container
- add MAC addresses to /home/peter/k8s/typhoon-bare-metal-new/dnsmasq/dnsmasq.conf

```
(py310) peter@peter-desktop-2022:~$ docker run --name dnsmasq --rm --cap-add=NET_ADMIN -v /home/peter/k8s/typhoon-bare-metal-new/dnsmasq/dnsmasq.conf:/etc/dnsmasq.conf:Z quay.io/poseidon/dnsmasq:latest
dnsmasq: started, version 2.83 cachesize 150
dnsmasq: compile time options: IPv6 GNU-getopt no-DBus no-UBus no-i18n no-IDN DHCP DHCPv6 no-Lua TFTP no-conntrack ipset auth no-nettlehash no-DNSSEC loop-detect inotify dumpfile
dnsmasq-dhcp: DHCP, IP range 172.17.0.50 -- 172.17.0.99, lease time 1h
dnsmasq-tftp: TFTP root is /var/lib/tftpboot  
dnsmasq: reading /etc/resolv.conf
dnsmasq: using nameserver 192.168.20.1#53
dnsmasq: read /etc/hosts - 7 addresses
```

### create Matchbox service

- generate TLS certificates via script in matchbox repo
```
(py310) peter@peter-desktop-2022:~$ export SAN=DNS.1:matchbox.secitec.net,IP.1:172.17.0.1
 (py310) peter@peter-desktop-2022:~/k8s/typhoon-bare-metal-new/tls$ ./cert-gen 
Creating example CA, server cert/key, and client cert/key...
Generating RSA private key, 4096 bit long modulus (2 primes)
...........++++
.................................................++++
e is 65537 (0x010001)
Generating RSA private key, 2048 bit long modulus (2 primes)
.................+++++
.....................+++++
e is 65537 (0x010001)
Using configuration from openssl.conf
Check that the request matches the signature
Signature ok
Certificate Details:
        Serial Number: 4096 (0x1000)
        Validity
            Not Before: Jun 14 20:37:43 2022 GMT
            Not After : Jun 14 20:37:43 2023 GMT
        Subject:
            commonName                = fake-server
        X509v3 extensions:
            X509v3 Basic Constraints: 
                CA:FALSE
            Netscape Cert Type: 
                SSL Server
            Netscape Comment: 
                OpenSSL Generated Server Certificate
            X509v3 Subject Key Identifier: 
                90:34:31:07:21:5E:4F:97:32:05:FA:32:84:70:18:3C:3C:13:C4:48
            X509v3 Authority Key Identifier: 
                keyid:0C:AE:3A:A7:B4:51:60:4F:34:7C:81:87:8E:CD:5F:9B:1C:36:24:76
                DirName:/CN=fake-ca
                serial:5E:E4:EA:DC:2F:FC:C9:E2:F7:47:DD:BD:E3:DF:E9:D9:ED:B2:1C:1D

            X509v3 Key Usage: critical
                Digital Signature, Key Encipherment
            X509v3 Extended Key Usage: 
                TLS Web Server Authentication
            X509v3 Subject Alternative Name: 
                DNS:matchbox.secitec.net, IP Address:172.17.0.1
Certificate is to be certified until Jun 14 20:37:43 2023 GMT (365 days)

Write out database with 1 new entries
Data Base Updated
Generating RSA private key, 2048 bit long modulus (2 primes)
.....+++++
...+++++
e is 65537 (0x010001)
Using configuration from openssl.conf
Check that the request matches the signature
Signature ok
Certificate Details:
        Serial Number: 4097 (0x1001)
        Validity
            Not Before: Jun 14 20:37:43 2022 GMT
            Not After : Jun 14 20:37:43 2023 GMT
        Subject:
            commonName                = fake-client
        X509v3 extensions:
            X509v3 Basic Constraints: 
                CA:FALSE
            Netscape Cert Type: 
                SSL Client
            Netscape Comment: 
                OpenSSL Generated Client Certificate
            X509v3 Subject Key Identifier: 
                88:F4:83:5A:1A:91:C2:CD:91:90:0A:C3:05:9B:7A:61:9C:11:46:84
            X509v3 Authority Key Identifier: 
                keyid:0C:AE:3A:A7:B4:51:60:4F:34:7C:81:87:8E:CD:5F:9B:1C:36:24:76

            X509v3 Key Usage: critical
                Digital Signature, Non Repudiation, Key Encipherment
            X509v3 Extended Key Usage: 
                TLS Web Client Authentication
Certificate is to be certified until Jun 14 20:37:43 2023 GMT (365 days)

Write out database with 1 new entries
Data Base Updated
*******************************************************************
WARNING: Generated credentials are self-signed. Prefer your
organization's PKI for production deployments.
 ```
 
 - copy certificates for matchbox service
``` 
 (py310) peter@peter-desktop-2022:~/k8s/typhoon-bare-metal-new/tls$ sudo cp server.* /etc/matchbox/
(py310) peter@peter-desktop-2022:~/k8s/typhoon-bare-metal-new/tls$ sudo cp ca.crt /etc/matchbox/
```

- run matchbox (binary download to /usr/local/bin):
```
(py310) peter@peter-desktop-2022:~$ sudo matchbox  -address=0.0.0.0:8080 -rpc-address=0.0.0.0:8081 -log-level=debug
[sudo] password for peter:       
INFO[0000] Starting matchbox gRPC server on 0.0.0.0:8081 
INFO[0000] Using TLS server certificate: /etc/matchbox/server.crt 
INFO[0000] Using TLS server key: /etc/matchbox/server.key 
INFO[0000] Using CA certificate: /etc/matchbox/ca.crt to authenticate client certificates 
INFO[0000] Starting matchbox HTTP server on 0.0.0.0:8080 
```

- test matchbox service (necessary for terraform)
```
(py310) peter@peter-desktop-2022:~/k8s/typhoon-bare-metal-new/tls$ openssl s_client -connect matchbox.secitec.net:8081 -CAfile ca.crt -cert client.crt -key client.key 
CONNECTED(00000003)
depth=1 CN = fake-ca
verify return:1
depth=0 CN = fake-server
verify return:1
---
Certificate chain
 0 s:CN = fake-server
   i:CN = fake-ca
---
Server certificate
...
    Start Time: 1655292605
    Timeout   : 7200 (sec)
    Verify return code: 0 (ok)
    Extended master secret: no
    Max Early Data: 0
---
read R BLOCK
@^C
```

- check matchbox files
```
(py310) peter@peter-desktop-2022:/var/lib/matchbox$ find
.
./profiles
./ignition
./assets
./assets/flatcar
./assets/flatcar/current
./assets/flatcar/3139.2.2
./groups
```
Currently there are no files, they will be created by terraform

### terraform
- set DNS entry in opnsense unbound (necessary for terraform)
![b193eec6d260053b72a9856b4b1f6acf.png](:/cd20e757a15c47aaaf200a3e3e5fe645)

- terraform configuration
set nodes in /home/peter/k8s/typhoon-bare-metal-new/cluster.tf.

- ssh-agent
```
(py310) peter@peter-desktop-2022:~/k8s/typhoon-bare-metal-new$ ssh-add ~/.ssh/id_rsa
Identity added: /home/peter/.ssh/id_rsa (/home/peter/.ssh/id_rsa)
(py310) peter@peter-desktop-2022:~/k8s/typhoon-bare-metal-new$ ssh-add -L
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCeyOuElMC2K8hQ7XRv/ii57Lyh8Q2PWhwiDtZZo588Vjw+TigH+ax692pfYiw6c1aQjeDewvf8PJMjEbt1QLm7PHrbDHELK6GVjhDQKwPppFmEVU8IbFYYDj9I5o2e5bDF0bajotvd1S0kCGChJes+wy++oELcB2FL/5BvjSrP1VvBGD4RX0Km6M978YXm9KFSdToFGuukO/x6RMCELA4NrwPCbl5hy+NPyc6Xi7VUjgUBfugAdqNNFHCA9mNxJVLZ0UaETbgwlUifS7Ensr5a5Dp1AEswd04/SXzFyiUg8IHjRsNM1Y0T1BkJNxT9c6yjMW3XkUUYcjfhzSRQj/N1 /home/peter/.ssh/id_rsa
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID3IMo2mGjaCIx+hOpdXup3turk2olEbjFKHFwA1a9vZ peter@Peter-Desktop-2020
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINT1aY5ZQTKDOFiE75qbYKsAjMN1vpqOa79pIGydlVPw peda@peda-desktop
```

- terraform debug
```
(py310) peter@peter-desktop-2022:~/k8s/typhoon-bare-metal-new$ export TF_LOG=DEBUG
```
- terraform init
```
(py310) peter@peter-desktop-2022:~/k8s/typhoon-bare-metal-new$ terraform init
Initializing modules...
Downloading git::https://github.com/poseidon/typhoon?ref=v1.24.1 for mercury...
- mercury in .terraform/modules/mercury/bare-metal/flatcar-linux/kubernetes
Downloading git::https://github.com/poseidon/terraform-render-bootstrap.git?ref=f325be50417e27dde6599a293409cb7d068cda0c for mercury.bootstrap...
- mercury.bootstrap in .terraform/modules/mercury.bootstrap

Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/template versions matching "~> 2.2"...
- Finding hashicorp/null versions matching ">= 2.1.0"...
- Finding hashicorp/tls versions matching "~> 3.2"...
- Finding hashicorp/random versions matching "~> 3.1"...
- Finding poseidon/ct versions matching "~> 0.9, 0.10.0"...
- Finding poseidon/matchbox versions matching "0.5.0, ~> 0.5.0"...
- Installing poseidon/matchbox v0.5.0...
- Installed poseidon/matchbox v0.5.0 (self-signed, key ID 8F515AD1602065C8)
- Installing hashicorp/template v2.2.0...
- Installed hashicorp/template v2.2.0 (signed by HashiCorp)
- Installing hashicorp/null v3.1.1...
- Installed hashicorp/null v3.1.1 (signed by HashiCorp)
- Installing hashicorp/tls v3.4.0...
- Installed hashicorp/tls v3.4.0 (signed by HashiCorp)
- Installing hashicorp/random v3.3.1...
- Installed hashicorp/random v3.3.1 (signed by HashiCorp)
- Installing poseidon/ct v0.10.0...
- Installed poseidon/ct v0.10.0 (self-signed, key ID 8F515AD1602065C8)

Partner and community providers are signed by their developers.
If you'd like to know more about provider signing, you can read about it here:
https://www.terraform.io/docs/cli/plugins/signing.html

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```
- terraform apply
This command creates all the matchbox files and waits until the VMs are reachable using SSH. 

### start vms in virt-manager
![97948c70940d71d47167e094c2455de8.png](:/035d55794fe547e084c82e9273c2e176)

-> ideally, the vms will be provisioned with the settings generated by terraform
```
module.mercury.null_resource.copy-worker-secrets[1] (remote-exec):   SSH Agent: true
module.mercury.null_resource.copy-worker-secrets[1] (remote-exec):   Checking Host Key: false
module.mercury.null_resource.copy-worker-secrets[1] (remote-exec):   Target Platform: unix
module.mercury.null_resource.copy-worker-secrets[1] (remote-exec): Connected!
module.mercury.null_resource.copy-worker-secrets[1]: Creation complete after 7m6s [id=5167009325835431594]
module.mercury.null_resource.bootstrap: Creating...
module.mercury.null_resource.bootstrap: Provisioning with 'remote-exec'...
module.mercury.null_resource.bootstrap (remote-exec): Connecting to remote host via SSH...
module.mercury.null_resource.bootstrap (remote-exec):   Host: node01.secitec.net
module.mercury.null_resource.bootstrap (remote-exec):   User: core
module.mercury.null_resource.bootstrap (remote-exec):   Password: false
module.mercury.null_resource.bootstrap (remote-exec):   Private key: false
module.mercury.null_resource.bootstrap (remote-exec):   Certificate: false
module.mercury.null_resource.bootstrap (remote-exec):   SSH Agent: true
module.mercury.null_resource.bootstrap (remote-exec):   Checking Host Key: false
module.mercury.null_resource.bootstrap (remote-exec):   Target Platform: unix
module.mercury.null_resource.bootstrap (remote-exec): Connected!
module.mercury.null_resource.bootstrap: Still creating... [10s elapsed]
module.mercury.null_resource.bootstrap: Still creating... [20s elapsed]
module.mercury.null_resource.bootstrap: Still creating... [30s elapsed]
module.mercury.null_resource.bootstrap: Creation complete after 36s [id=2908521641360419294]
```

## Result
```
(py310) peter@peter-desktop-2022:~/k8s/typhoon-bare-metal-new$ export KUBECONFIG=kubeconfig 
(py310) peter@peter-desktop-2022:~/k8s/typhoon-bare-metal-new$ k get nodes -o wide
NAME                 STATUS   ROLES    AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                                             KERNEL-VERSION    CONTAINER-RUNTIME
node01.secitec.net   Ready    <none>   10m   v1.24.1   172.17.0.21   <none>        Flatcar Container Linux by Kinvolk 3139.2.2 (Oklo)   5.15.43-flatcar   containerd://1.5.11
node02.secitec.net   Ready    <none>   10m   v1.24.1   172.17.0.22   <none>        Flatcar Container Linux by Kinvolk 3139.2.2 (Oklo)   5.15.43-flatcar   containerd://1.5.11
node03.secitec.net   Ready    <none>   10m   v1.24.1   172.17.0.23   <none>        Flatcar Container Linux by Kinvolk 3139.2.2 (Oklo)   5.15.43-flatcar   containerd://1.5.11
(py310) peter@peter-desktop-2022:~/k8s/typhoon-bare-metal-new$ kubectl get pods --all-namespaces
NAMESPACE     NAME                                         READY   STATUS    RESTARTS        AGE
kube-system   cilium-26m7l                                 1/1     Running   1 (7m41s ago)   10m
kube-system   cilium-5j764                                 1/1     Running   0               10m
kube-system   cilium-dsbjz                                 1/1     Running   1 (7m41s ago)   10m
kube-system   cilium-operator-7f9d658fb5-82hmp             1/1     Running   0               10m
kube-system   coredns-6b956c844d-26h4h                     1/1     Running   0               10m
kube-system   coredns-6b956c844d-zf6s2                     1/1     Running   0               10m
kube-system   kube-apiserver-node01.secitec.net            1/1     Running   0               9m1s
kube-system   kube-controller-manager-node01.secitec.net   1/1     Running   2 (12m ago)     9m39s
kube-system   kube-proxy-dwgwq                             1/1     Running   0               10m
kube-system   kube-proxy-lbz6b                             1/1     Running   0               10m
kube-system   kube-proxy-lhk6z                             1/1     Running   0               10m
kube-system   kube-scheduler-node01.secitec.net            1/1     Running   0               9m48s
```

## Day 2 - manual
### Flatcar linux update operator
via https://github.com/flatcar-linux/flatcar-linux-update-operator

```
core@node03 ~ $ sudo systemctl unmask update-engine.service
core@node03 ~ $ sudo systemctl enable update-engine.service --now
core@node03 ~ $ sudo systemctl mask locksmithd.service           
core@node03 ~ $ sudo systemctl stop locksmithd.service
```

### Set static addresses
```
node03 /etc/systemd/network # cat static.network 
[Match]
Name=ens3

[Network]
Address=172.17.0.23/24
Gateway=172.17.0.1
DNS=192.168.20.1
```

## Day 2 - ansible
**flatcar does not have a python interpreter installed, just download a pypy binary and use that one**

```
(py310) peter@peter-desktop-2022:~/k8s/typhoon-bare-metal-new$ ansible-playbook pb-flatcar-day2.yml 

PLAY [day2_operations_flatcar_linux_get_python] *********************************************************************************************************************************************************************

TASK [get python] ***************************************************************************************************************************************************************************************************
changed: [172.17.0.22]
changed: [172.17.0.23]
changed: [172.17.0.21]

PLAY [day2_operations_flatcar_linux] ********************************************************************************************************************************************************************************

TASK [Gathering Facts] **********************************************************************************************************************************************************************************************
ok: [172.17.0.22]
ok: [172.17.0.23]
ok: [172.17.0.21]

TASK [Enable service update-engine] *********************************************************************************************************************************************************************************
ok: [172.17.0.23]
ok: [172.17.0.22]
ok: [172.17.0.21]

TASK [Disable service locksmithd] ***********************************************************************************************************************************************************************************
ok: [172.17.0.22]
ok: [172.17.0.23]
ok: [172.17.0.21]

TASK [Template a file to /etc/systemd/network/static.network] *******************************************************************************************************************************************************
ok: [172.17.0.22]
ok: [172.17.0.23]
ok: [172.17.0.21]

PLAY RECAP **********************************************************************************************************************************************************************************************************
172.17.0.21                : ok=5    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
172.17.0.22                : ok=5    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
172.17.0.23                : ok=5    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
```


