docker --version

if [ $? -eq 0 ]; then
  echo -e "$(docker --version) found, running sonarqube on docker port 9000"
  docker run -d --name sonar -p 9000:9000 sonarqube:lts-community
  else
    echo -e "installing docker"
    labauto docker.sh
    echo -e "Installed $(docker --version), running sonarqube on docker port 9000"
    docker run -d --name sonar -p 9000:9000 sonarqube:lts-community
    echo -e "access sonarqube on http://localhost:9000 (or) http://domain.com:9000"
fi