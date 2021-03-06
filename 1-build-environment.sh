#!/bin/bash
echo "Welcome to the OSS Demo Jumpbox install process.  This script will:"
echo "    - Install git"
echo "    - Install Azure CLI if not present"
echo "    - Log in to Azure and create a Resource Group 'ossdemo-utility' and CENTOS VM"
echo "  Script currently works against Ubuntu, Centos and RHEL however we are working through a bug with OSX regarding Ansible host length."
echo ""
echo "Installation will require SU rights."
echo ""
echo "Installing git & ansible if they are missing."
echo "Starting:"$(date)
#Check DISTRO
echo "Checking OS Distro"
if [ -f /etc/redhat-release ]; then
  echo "    found RHEL or CENTOS - proceeding with YUM."
  sudo yum update -y
  yum install epel-release
  yum install -y python-pip
  sudo yum -y install git
  sudo yum install gcc libffi-devel python-devel openssl-devel -y
  sudo yum install ansible
  
  
fi
if [ -f /etc/lsb-release ]; then
  echo "    Ubuntu - proceeding with APT."
  gitinfo=$(dpkg-query -W -f='${Package} ${Status} \n' git | grep "git install ok installed")
  if [[ $gitinfo =~ "git install ok installed" ]]; then
     echo "   git installed - skipping"
  else  
     echo "   could not find git - installing...."
     sudo apt-get install git -y
  fi
   sudo apt-get install software-properties-common -y
   sudo apt-add-repository ppa:ansible/ansible -y
   sudo apt-get update -y
   sudo apt-get install build-essential -y
   sudo apt-get install libssl-dev libffi-dev python-dev -y
   sudo apt-get install ansible -y
      
fi
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "  OSType is:" ${OSTYPE}
    echo "    MAC Darwin - proceeding with specialized MAC install."
    
    sudo easy_install pip
    sudo pip install ansible
fi

echo ""
echo "Installing AZ command line tools if they are missing."
#Check to see if Azure is installed if not do it...
if [ -f ~/bin/az ]
  then
    echo "    AZ Client installed. Skipping install.."
  else
    curl -L https://aka.ms/InstallAzureCli | bash
    exec -l $SHELL
fi
echo "Checking for Azure CLI upgrades"
az component update
echo ""
echo "Logging in to Azure"
#Checking to see if we are logged into Azure
echo "    Checking if we are logged in to Azure."
#We need to redirect the output streams to stdout
azstatus=`~/bin/az group list 2>&1` 
if [[ $azstatus =~ "Please run 'az login' to setup account." ]]; then
   echo "   We need to login to azure.."
   ~/bin/az login
else
   echo "    Logged in."
fi
read -p "    Change default subscription? [y/n]:" changesubscription
if [[ $changesubscription =~ "y" ]];then
    read -p "      New Subscription Name:" newsubscription
    ~/bin/az account set --subscription "$newsubscription"
else
    echo "    Using default existing subscription."
fi

echo ""
echo "Set values for creation of resource groups and jumpbox server"
# Check the validity of the name (no dashes, spaces, less than 8 char, no special chars etc..)
# Can we set a Enviro variable so if you want to rerun it is here and set by default?
echo "    Please enter your unique server prefix: (Jumpbox server will become:'jumpbox-PREFIX')"
echo "      Note - values should be lowercase and less than 8 characters.')" 
read -p "Server Prefix:" serverPrefix
# This requires a newer version of BASH not avialble in MAC OS - serverPrefix=${serverPrefix,,} 
serverPrefix=$(echo "${serverPrefix}" | tr '[:upper:]' '[:lower:]')
echo ""


### JUMPBOX SERVER PASSWORD
echo ""
echo "Set initial password for jumpbox server:"
stty -echo
read jumpboxPassword
stty echo
echo ""

# Check the validity of the name (no dashes, spaces, less than 8 char, no special chars etc..)"
# Can we set a Enviro variable so if you want to rerun it is here and set by default?
echo "    Please enter your unique storage prefix: (Storage Account will become: 'PREFIX-storage'')"
echo "      Note - values should be lowercase and less than 8 characters.')"
read -p  "Storage Prefix? (default: ${serverPrefix}): " storagePrefix
[ -z "${storagePrefix}" ] && storagePrefix=${serverPrefix}

#read -e -i "$serverPrefix" -p "Storage Prefix: " storagePrefix

# This requires a newer version of BASH not avialble in MAC OS - storagePrefix=${storagePrefix,,} 
storagePrefix=$(echo "${storagePrefix}" | tr '[:upper:]' '[:lower:]')
echo "${storagePrefix}"

echo ""
read -p "Create resource group, and network rules? [y/n]:"  continuescript
if [[ $continuescript != "n" ]];then

#BUILD RESOURCE GROUPS
echo ""
echo "BUILDING RESOURCE GROUPS"
echo "Starting:"$(date)
echo "--------------------------------------------"
echo 'create utility resource group'
~/bin/az group create --name ossdemo-utility --location eastus

#BUILD NETWORKS SECURTIY GROUPS and RULES
echo ""
echo "BUILDING NETWORKS, SECURTIY GROUPS and RULES"
echo "Starting:"$(date)
echo "--------------------------------------------"
echo 'Network Security Group for utility Resource Group'
~/bin/az network nsg create --resource-group ossdemo-utility --name NSG-ossdemo-utility --location eastus

echo 'Allow RDP inbound to Utility'
~/bin/az network nsg rule create --resource-group ossdemo-utility \
     --nsg-name NSG-ossdemo-utility --name rdp-rule \
     --access Allow --protocol Tcp --direction Inbound --priority 100 \
     --source-address-prefix Internet \
     --source-port-range "*" --destination-address-prefix "*" \
     --destination-port-range 3389
 echo 'Allow SSH inbound to Utility'
 ~/bin/az network nsg rule create --resource-group ossdemo-utility \
     --nsg-name NSG-ossdemo-utility --name ssh-rule \
     --access Allow --protocol Tcp --direction Inbound --priority 110 \
     --source-address-prefix Internet \
     --source-port-range "*" --destination-address-prefix "*" \
     --destination-port-range 22

echo "----------------------------------"
echo "Create VNET - az network vnet create -n 'ossdemo-utility-vnet' -g ossdemo-utility"
        az network vnet create -n 'ossdemos-vnet' -g ossdemo-utility --address-prefix 192.168.0.0/16
echo " Create Subnet: 192.168.0.0/24"
echo "    running - az network vnet subnet create -g ossdemo-utility-iaas --vnet-name ossdemos-vnet -n ossdemo-utility-subnet --address-prefix 192.168.0.0/24 --network-security-group NSG-ossdemo-utility"
        az network vnet subnet create -g ossdemo-utility --vnet-name ossdemos-vnet -n ossdemo-utility-subnet --address-prefix 192.168.0.0/24 --network-security-group NSG-ossdemo-utility
echo "----------------------------------"


fi
echo ""
read -p "Create storage accounts and jumpbox server? [y/n]:"  continuescript
if [[ $continuescript != "n" ]];then

#BUILD STORAGE ACCOUNTS
echo ""
echo "BUILDING STORAGE ACCOUNTS"
echo "Starting:"$(date)
echo "--------------------------------------------"
echo "Create Utility Storage account - you may need to change this in case there is a conflict"
echo "this is used in VM Create (Diagnostics storage) and Azure Registry"
echo "calling ~/bin/az storage account create -l eastus -n ${storagePrefix}storage -g ossdemo-utility --sku Standard_LRS"
~/bin/az storage account create -l eastus -n ${storagePrefix}storage -g ossdemo-utility --sku Standard_LRS

#Looking for jumpbox ssh key - if not found create one
echo "We are creating a new VM with SSH enabled.  Looking for an existing key or creating a new one."
if [ -f ~/.ssh/jumpbox_${serverPrefix}_id_rsa ]
  then
    echo "    Existing private key found.  Using this key ~/.ssh/jumpbox_${serverPrefix}_id_rsa for jumpbox creation"
  else
    echo "    Creating new key for ssh in ~/.ssh/jumpbox_${serverPrefix}_id_rsa"
    #Create key
    ssh-keygen -f ~/.ssh/jumpbox_${serverPrefix}_id_rsa -N ""
    #Add this key to the ssh config file 
fi
if grep -Fxq "Host jumpbox-${serverPrefix}.eastus.cloudapp.azure.com" ~/.ssh/config
then
    # Replace the server with the right private key
    # BUG BUG - we need to actually replace the next three lines with new values
    # sed -i "s@*Host jumpbox-${serverPrefix}.eastus.cloudapp.azure.com*@Host=jumpbox-${serverPrefix}.eastus.cloudapp.azure.com IdentityFile=~/.ssh/jumpbox_${serverPrefix}_id_rsa User=GBBOSSDemo@g" ~/.ssh/config
    echo "  We found an entry in ~/.ssh/config for this server - do not recreate."
else
    # Add this to the config file
    echo -e "Host=jumpbox-${serverPrefix}.eastus.cloudapp.azure.com\nIdentityFile=~/.ssh/jumpbox_${serverPrefix}_id_rsa\nUser=GBBOSSDemo" >> ~/.ssh/config
fi
sudo chmod 600 ~/.ssh/config
sudo chmod 600 ~/.ssh/jumpbox*
sshpubkey=$(< ~/.ssh/jumpbox_${serverPrefix}_id_rsa.pub)

#CREATE UTILITY JUMPBOX SERVER
echo ""
echo "Creating CENTOS JUMPBOX utility machine for RDP and ssh"
echo "Starting:"$(date)
echo "Reading ssh key information from local jumpbox_${serverPrefix}_id_rsa file"
echo "--------------------------------------------"
azcreatecommand="-g ossdemo-utility -n jumpbox-${serverPrefix} --public-ip-address-dns-name jumpbox-${serverPrefix} --os-disk-name jumpbox-${serverPrefix}-disk --image OpenLogic:CentOS:7.2:latest --nsg NSG-ossdemo-utility  --storage-sku Premium_LRS --size Standard_DS2_v2 --vnet-name ossdemos-vnet --subnet ossdemo-utility-subnet --admin-username gbbossdemo --ssh-key-value ~/.ssh/jumpbox_${serverPrefix}_id_rsa.pub "
echo " Calling command: ~/bin/az vm create ${azcreatecommand}"
~/bin/az vm create ${azcreatecommand}
fi

read -p "Please confirm the server is running in the Azure portal before continuing. [press any key to continue]:" 

#Download the GIT Repo for keys etc.
echo "--------------------------------------------"
echo "Ensuring we are in the /source directory for Ansible scripts."
sudo mkdir /source
cd /source
echo ""
echo "--------------------------------------------"
echo "Configure jumpbox server with ansible"
echo "Starting:"$(date)
sudo sed -i -e "s@JUMPBOXSERVER-REPLACE.eastus.cloudapp.azure.com@jumpbox-${serverPrefix}.eastus.cloudapp.azure.com@g" /source/OSSonAzure/ansible/hosts
cd /source/OSSonAzure/ansible
echo ""
ansiblecommand=" -i /source/OSSonAzure/ansible/hosts /source/OSSonAzure/ansible/jumpbox-server-configuration.yml --private-key ~/.ssh/jumpbox_${serverPrefix}_id_rsa"
echo "Calling command: ansible-playbook ${ansiblecommand}"
ansible-playbook ${ansiblecommand}
echo ""
echo "---------------------------------------------"
echo "Configure demo template values file"
sudo sed -i -e "s@JUMPBOX-SERVER-NAME=@JUMPBOX-SERVER-NAME=jumpbox-${serverPrefix}.eastus.cloudapp.azure.com@g" /source/OSSonAzure/vm-assets/DemoEnvironmentTemplateValues
sudo sed -i -e "s@DEMO-STORAGE-ACCOUNT=@DEMO-STORAGE-ACCOUNT=${storagePrefix}storage@g" /source/OSSonAzure/vm-assets/DemoEnvironmentTemplateValues


#Set the remote jumpbox passwords
echo "Resetting GBBOSSDemo and root passwords based on script values."
echo "Starting:"$(date)
ssh gbbossdemo@jumpbox-${serverPrefix}.eastus.cloudapp.azure.com -i ~/.ssh/jumpbox_${serverPrefix}_id_rsa 'echo "gbbossdemo:${jumpboxPassword}" | sudo chpasswd'
ssh gbbossdemo@jumpbox-${serverPrefix}.eastus.cloudapp.azure.com -i ~/.ssh/jumpbox_${serverPrefix}_id_rsa 'echo "root:${jumpboxPassword}" | sudo chpasswd'

#Copy the SSH private & public keys up to the jumpbox server
echo "Copying up the SSH Keys for demo purposes to the jumpbox ~/.ssh directories for GBBOSSDemo user."
echo "Starting:"$(date)
scp ~/.ssh/jumpbox_${serverPrefix}_id_rsa gbbossdemo@jumpbox-${serverPrefix}.eastus.cloudapp.azure.com:~/.ssh/id_rsa
scp ~/.ssh/jumpbox_${serverPrefix}_id_rsa.pub gbbossdemo@jumpbox-${serverPrefix}.eastus.cloudapp.azure.com:~/.ssh/id_rsa.pub
ssh gbbossdemo@jumpbox-${serverPrefix}.eastus.cloudapp.azure.com -i ~/.ssh/jumpbox_${serverPrefix}_id_rsa 'sudo chmod 600 ~/.ssh/id_rsa'

#mkdir for source on jumpbox server
echo "Copying the template values file to the jumpbox server in /source directory."
echo "Starting:"$(date)
ssh gbbossdemo@jumpbox-${serverPrefix}.eastus.cloudapp.azure.com -i ~/.ssh/jumpbox_${serverPrefix}_id_rsa 'sudo mkdir /source'
scp /source/OSSonAzure/DemoEnvironmentTemplateValues gbbossdemo@jumpbox-${serverPrefix}.eastus.cloudapp.azure.com:/source/DemoEnvironmentTemplateValues

echo ""
echo "Launch Microsoft or MAC RDP via --> mstsc and enter your jumpbox servername:jumpbox-${serverPrefix}.eastus.cloudapp.azure.com" 
echo "   or leverage the RDP file created in /source/JUMPBOX-SERVER.rdp"
sudo sed -i -e "s@JUMPBOX-SERVER-NAME@jumpbox-${serverPrefix}@g" /source/OSSonAzure/vm-assets/JUMPBOX-SERVER.rdp
sudo cp /source/OSSonAzure/vm-assets/JUMPBOX-SERVER.rdp /source/OSSDemo-jumpbox-server.rdp
echo "SSH is available via: ssh GBBOSSDemo@jumpbox-${serverPrefix}.eastus.cloudapp.azure.com -i ~/.ssh/jumpbox_${serverPrefix}_id_rsa "
echo ""
echo "Enjoy and please report any issues in the GitHub issues page or email GBBOSS@Microsoft.com..."
echo ""
echo "Finished:"$(date)