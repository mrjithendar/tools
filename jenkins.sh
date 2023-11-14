## INSTALL JENKINS ##
echo "Installing Java"
yum remove java* -y
yum -y install java-11-openjdk java-11-openjdk-devel
yum install -y fontconfig

# update-alternatives --config java

echo "addiing jenkins repos"
wget --no-check-certificate -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key

echo "Installing Jenkins"
yum install jenkins --nogpgcheck -y

mkdir -p /var/lib/jenkins/.ssh
echo 'Host *
    UserKnownHostsFile /dev/null
    StrictHostKeyChecking no' >/var/lib/jenkins/.ssh/config
chown jenkins:jenkins /var/lib/jenkins/.ssh -R
chmod 400 /var/lib/jenkins/.ssh/config

sudo usermod -aG root jenkins
usermod -s /bin/bash jenkins

sed -i -e 's/JENKINS_USER="jenkins"/JENKINS_USER="root"/' /etc/sysconfig/jenkins

systemctl enable jenkins && systemctl restart jenkins

echo "::::JENKINS MASTER PASSWORD::::"
cat /var/lib/jenkins/secrets/initialAdminPassword
#1bd5416fe7f245f5876b0b6a5183d977