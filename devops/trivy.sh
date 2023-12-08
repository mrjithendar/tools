echo '[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$releasever/$basearch/
gpgcheck=0
enabled=1' > /etc/yum.repos.d/trivy.repo

#sudo yum -y update
sudo yum -y install trivy