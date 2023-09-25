## INSTALL JENKINS ##
echo "Installing Java"
yum install fontconfig java-17-openjdk -y

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