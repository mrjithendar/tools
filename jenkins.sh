## INSTALL JENKINS ##
echo "Installing Java"
yum remove java* -y
yum yum -y install java-11-openjdk java-11-openjdk-devel
yum install -y fontconfig

# update-alternatives --config java

echo "addiing jenkins repos"
wget --no-check-certificate -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key

echo "Installing Jenkins"
yum install jenkins --nogpgcheck -y
systemctl enable jenkins && systemctl restart jenkins
mkdir -p /var/lib/jenkins/.ssh
echo 'Host *
    UserKnownHostsFile /dev/null
    StrictHostKeyChecking no' >/var/lib/jenkins/.ssh/config
chown jenkins:jenkins /var/lib/jenkins/.ssh -R
chmod 400 /var/lib/jenkins/.ssh/config

cat /var/lib/jenkins/secrets/initialAdminPassword