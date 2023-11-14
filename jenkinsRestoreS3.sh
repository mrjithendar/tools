mkdir /tmp/jenkins/

echo 'Downloading jenkins_backup.tar from S3 bucket'
aws s3 cp s3://jithendardharmapuri/jenkins_backup.tar /tmp/jenkins/jenkins_backup.tar

echo 'Extracting jenkins_backup.tar /tmp/jenkins'
tar -xvf /tmp/jenkins/jenkins_backup.tar --directory /tmp/jenkins/

JENKINS_HOME=/var/lib/jenkins

rm -rf $JENKINS_HOME
mv -r /tmp/jenkins/jenkins $JENKINS_HOME