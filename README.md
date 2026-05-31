# Kubernetes On Proxmox With Terraform And Ansible

Configuration and documentation for how to set up Kubernetes on Proxmox with Cloud Init, Ubuntu, TerraForm and Ansible


## Kubereats Target Architecture

This fork is configured for the Kubereats on-prem Kubernetes VM layer across two Proxmox hosts, with four edge ingress-capable workers prepared for a future GCP Global HTTPS Load Balancer + Hybrid NEG path. See [docs/kubereats-architecture.md](docs/kubereats-architecture.md) for the VM inventory, IP plan, Terraform outputs, Ansible command sequence, and current HA limitations.

This repository intentionally does not manage PostgreSQL, DB VMs, Patroni, pgBackRest, GCS backup, Redis, GCP load balancer resources, or production MetalLB ingress.

## Advisory

This set of instructions has been tested on Ubuntu VMs running on Proxmox, and cloned using cloud-init.

You should run these setup commands from an Infrastructure as Code staging VM, separate from the Kubernetes cluster, but can be your workstation if you run on Linux natively.

**Note - WSL has some file system limitations that will make the installation hard with Ansible and private keys. It does work perfectly for running kubectl commands as per the latter parts of these instructions.**

**Further Note - You may be tempted to try LXC on Proxmox instead of using VMs but it throws errors on the Kubernetes installation swap memory step.**


The Terraform files are designed to work with the Ubuntu 24.04 cloud-init image.
You will also need to customise your image as per [https://youtu.be/HbBblJOZs-c](https://youtu.be/HbBblJOZs-c)


## Pre-requisites

You will need the following to be installed and set up on your Infrastructure as Code machine:

- Terraform
- Ansible
- sshpass

These can all be installed using:

```
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | \
gpg --dearmor | \
sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
```
Verify the hashicorp key using this command as here: [https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
```
gpg --no-default-keyring \
--keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
--fingerprint
```
Install the key and the rest of the packages:
```
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list


sudo apt-add-repository ppa:ansible/ansible
sudo apt update -y
sudo apt install ansible sshpass terraform -y

```

## SSH Key Setup

Setup the cloud-init image as previously, but an sshkey is required for this configuration so will need to be generated as per [https://developer.hashicorp.com/terraform/tutorials/provision/cloud-init](https://developer.hashicorp.com/terraform/tutorials/provision/cloud-init)

```
ssh-keygen -t rsa -C "your_email@example.com" -f ./tf-cloud-init
```

When prompted, press enter to leave the passphrase blank on this key.

You will need to copy the key into the Terraform files, and will reference it in Ansible and SSH connections.

In advance of running Ansible, run the following command to update the permissings on the tf-cloud-init private key:
```
chmod 400 tf-cloud-init
```

## Terraform Setup
Kubereats-specific Terraform defaults now live in `terraform/vars.tf` and are documented in `docs/kubereats-architecture.md`. Use that architecture note as the authoritative command sequence and inventory for this fork; some older upstream examples below are retained for general background only.


Terraform will do the heavy lifting with creating the VMs for the Kubernetes cluster.
Customise the main.tf with Proxmox Provider details:
- pm_api_url.
- pm_user and pm_password or pm_api_token_id and pm_api_token_secret.
- target_node for the k8s-master and k8s-node sections.

You should also set:
- Relevant IP addresses, DNS and Gateway details for your environment.
- VMIDs (these are important as they stop Proxmox trying to re-use the same VMID immediately).
- cloud-init template name.
- SSH public key values 

With these configured, run the following in the terraform subdirectory.
```
terraform init
terraform apply
```

Confirm the terraform apply by typing "yes" and wait for the cloning to complete.

## Ansible Setup
For this fork, `ansible/k8s-inventory.yml` defines `k8s-cp-01` as the bootstrap control plane, `k8s-cp-02` as a control-plane candidate, and four edge ingress-capable workers. The current playbooks keep the single-bootstrap kubeadm flow and do not perform `kubeadm join --control-plane`.


Ansible is used to setup Kubernetes, and this part of the setup can effectively be used on any appropriate machines, physical or virtual.

First edit the k8s-inventory.yml file, updating the following:
- IP addresses for k8s_master and each k8s_node.
- The cluster network.
- The ansible_user, ansible_password and ansible_become_password (sudo password).
- Any other options that you want to customise.

Next, run the following command in the ansible subdirectory to apply the Kubernetes dependencies.
```
ansible-playbook k8s-setup.yml -i k8s-inventory.yml  --key-file ../tf-cloud-init
```
The playbook will run and configure all the Kubernetes machines with the required dependencies.

When this has completed, run the following:
```
ansible-playbook k8s-master.yml -i k8s-inventory.yml --key-file ../tf-cloud-init
```
This will configure your designated k8s-master VM as the Kubernetes master node.

## Building the cluster

The final steps to building the Kubernetes cluster are to run join commands - this can be automated via the join-nodes.sh script (which is the recommended approach), but the individual commands are as follows.

On the master, get the join token and command:
```
sudo kubeadm token create --print-join-command
```

Copy the command and run this on each node, eg:
```
kubeadm join 192.168.5.230:6443 --token 3q80fq.sza8m3z1qkode5bo --discovery-token-ca-cert-hash sha256:de4f0507d6984fd0048289f0aa62e09bcc393c217105894e855a4ad9a43b642f
```
To connect to each node, you will need to specify the public key as part of the ssh connection, eg:
```
ssh user@192.168.5.230 -i tf-cloud-init -o StrictHostKeyChecking=no
```
When the join commands have run, you should be able to run the following command on the k8s-master to see the nodes in the cluster.

```
user@k8s-master:~$ sudo kubectl get nodes

NAME         STATUS     ROLES           AGE     VERSION
k8s-master   Ready      control-plane   5m      v1.32.2
k8s-node1    NotReady   <none>          2m      v1.32.2
k8s-node2    Ready      <none>          1m      v1.32.2
k8s-node3    Ready      <none>          30s     v1.32.2

```

Instead of using the join commands, you can instead update and run the join-nodes.sh script.
Update the following on the staging machine:
- Either create hostname entries in /etc/hosts for the kubernetes hosts and IPs, eg:
```
192.168.5.230 k8s-master
192.168.5.231 k8s-node1
192.168.5.232 k8s-node2
192.168.5.233 k8s-node3
```
- Or edit the script to replace the hostnames with the relevant IP addresses, eg:
```
# Variables - modify these as needed
MASTER_NODE="192.168.5.230"
WORKER_NODES=("192.168.5.231" "192.168.5.232" "192.168.5.233")
SSH_USER="user"
SSH_OPTIONS="-o StrictHostKeyChecking=no -i tf-cloud-init"
```
- Update the SSH_USER name if required.

Run the script using:
```
./join-nodes.sh
```
When the script finishes, you should be able to see the nodes as present using "sudo kubectl get nodes" as described above.

You should now have a working Kubernetes cluster.

The join-nodes.sh script will also copy the Kubernetes cluster /etc/kubernetes/admin.conf file back to the staging machine as /home/$USER/.kube/conf, allowing kubectl to be run from there if this is desired.

## Testing the cluster using Nginx and NodePort

Services in Kubernetes run by default without being exposed to networks outside the cluster, and need to be configured for this.
On cloud services, there is integration for load balancers, but with a bare-metal or home lab Kubernetes cluster, you are unlikely to have this.
NodePort provides an alternative to load balancing, but will expose the service on only one node. If the node goes offline, the service will not be available - and it can also move if not configured for a specific node.
NodePort is fine for testing purposes.

Note: You can connect to the Kubernetes master from the staging machine using:
```
ssh user@192.168.5.230 -i tf-cloud-init -o StrictHostKeyChecking=no 
```
Download the nginx-nodeport-test.yml file from the repo (wget nginx-nodeport-test.yml) or copy the nginx-nodeport-test.yml file to the kubernetes master, and run:
```
sudo kubectl apply -f nginx-nodeport-test.yml
```
You can then confirm which node the service is running on using the following command:
```
user@k8s-master:~$ sudo kubectl get pods -o wide
```
The response should show something like the following:
```
NAME                         READY   STATUS    RESTARTS   AGE   IP           NODE        NOMINATED NODE   READINESS GATES
app-server-5888f8477-zlr2g   1/1     Running   0          24h   10.244.3.5   k8s-node3   <none>           <none>
```
The node on which the service is running is k8s-node3 - you should be able to infer the IP address of this from your configuration, and connect to it on port 3200 using your browser or by curl command, eg.
```
curl http://192.168.5.233:32000/
```
The default nginx page should be returned.

**Note - NodePort is not correctly explained in the video as traffic will be routed from any node to the node running the service. Using any IP in the cluster should allow the connection.**

There is a nice overview of different ways to expose services [here](https://medium.com/@seanlinsanity/how-to-expose-applications-running-in-kubernetes-cluster-to-public-access-65c2fa959a3b) by [Sean Lin](https://medium.com/@seanlinsanity), and from which the nginx NodePort test has been taken. 

# Bonus Content - Additional configuration

This content relates to [https://youtu.be/4pIapR-Ci74](https://youtu.be/4pIapR-Ci74).

You should have a working, tested Kubernetes cluster at this point, but there are a few additional components that you may wish to install for ease of use and extra functionality. These are:
- Set up local access for Kubectl.
- Helm - to allow the use of helm charts.

**Note: The Kubernetes dashboard was also considered and explored, but most users will be better off with Lens in my opinion.**

## Setting up local access for Kubectl.

If you have been following these steps closely, you will have used an Infrastructure as Code staging machine to provision and then access the Kubernetes machines.

For ease of use going forward, we need a local toolset to access the Kubernetes cluster directly.

On your workstation, as per https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-using-native-package-management, you need to do the following:

```
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl
```

You can now run sudo kubectl cluster-info but it will effectively tell you that it can't find a cluster.

You need to copy the /etc/kubernetes/admin.conf file from the master node back to your workstation.
If you used the join-nodes.sh script, it should exist as /home/$USER/.kube/config on the Infrastructure as Code staging machine, and you can copy it back to your local machine as follows:

```
mkdir $HOME/.kube/
scp user@192.168.5.185:/home/user/.kube/config $HOME/.kube/

```
Alternatively, you will need to copy the /etc/kubernetes/admin.conf from the Kubernetes master back to your local machine directly - you should copy the the key files (tf-cloud-init and tf-cloud-init.pub) back to your local machine in order to do this. 

With the config file in place, you should now be able to run kubectl successfully if you specify the config file location, eg:

```
$ sudo kubectl get service --kubeconfig /home/$USER/.kube/config

NAME          TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
app-service   NodePort    10.101.69.93   <none>        80:32000/TCP   2d2h
kubernetes    ClusterIP   10.96.0.1      <none>        443/TCP        3d15h
```

The config file can also be used to run the Lens IDE, which is a good graphical UI for Kubernetes.


## Helm installation

As detailed here [https://helm.sh/docs/intro/install/](https://helm.sh/docs/intro/install/)

Run the following commands:

```
$ curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
$ chmod 700 get_helm.sh
$ ./get_helm.sh
```