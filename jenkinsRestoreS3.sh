mkdir /tmp/jenkins/

JENKINS_HOME=/var/lib/jenkins
rm -rf $JENKINS_HOME

systemctl stop jenkins

echo 'Downloading jenkins_backup.tar from S3 bucket'
aws s3 cp s3://jithendardharmapuri/jenkins_backup.tar /tmp/jenkins_backup.tar

echo 'Extracting jenkins_backup.tar /tmp/jenkins'
tar -xvf /tmp/jenkins_backup.tar --directory /tmp/jenkins/


mv /tmp/jenkins/* $JENKINS_HOME

systemctl start jenkins