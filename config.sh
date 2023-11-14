yum update -y

yum upgrade -y

yum install python3.11 python3.11 pip -y

ln -s /usr/bin/pip3.11 /usr/bin/python
ln -s /usr/bin/pip3.11 /usr/bin/pip

pip install checkov
pip install ansible