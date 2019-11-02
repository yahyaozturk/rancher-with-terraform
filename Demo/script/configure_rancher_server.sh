#!/bin/bash -x

rancher_server_ip=${1:-localhost}
default_password=${2:-password}
rancher_server_version=${3:-stable}
kubernetes_version=${4:-v1.11.2-rancher1-1}
registry_prefix="rancher"
curl_prefix="appropriate"

protocol="http"
rancher_command="rancher/rancher:$rancher_server_version" 

echo Installing Rancher Server
sudo docker run -d --restart=always \
 -p 443:443 \
 -p 80:80 \
 $rancher_env_vars \
 --restart=unless-stopped \
 --name rancher-server \
$rancher_command

echo Installing RQ package
sudo apt-get update
sleep 5
sudo apt-get install jq -y

# wait until rancher server is ready
while true; do
  wget -T 5 -c https://localhost/ping --no-check-certificate && break
  sleep 5
done

# Login
LOGINRESPONSE=$(docker run --net=host \
    --rm \
    $curl_prefix/curl \
    -s "https://127.0.0.1/v3-public/localProviders/local?action=login" -H 'content-type: application/json' --data-binary '{"username":"admin","password":"admin"}' --insecure)

LOGINTOKEN=$(echo $LOGINRESPONSE | jq -r .token)

# Change password
docker run --net=host \
    --rm \
    $curl_prefix/curl \
     -s "https://127.0.0.1/v3/users?action=changepassword" -H 'content-type: application/json' -H "Authorization: Bearer $LOGINTOKEN" --data-binary '{"currentPassword":"admin","newPassword":"'$default_password'"}' --insecure

# Create API key
APIRESPONSE=$(docker run --net host \
    --rm \
    $curl_prefix/curl \
     -s "https://127.0.0.1/v3/token" -H 'content-type: application/json' -H "Authorization: Bearer $LOGINTOKEN" --data-binary '{"type":"token","description":"automation","name":""}' --insecure)

# Extract and store token
APITOKEN=$(echo $APIRESPONSE | jq -r .token)

# Configure server-url
SERVERURLRESPONSE=$(docker run --net host \
    --rm \
    $curl_prefix/curl \
     -s 'https://127.0.0.1/v3/settings/server-url' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" -X PUT --data-binary '{"name":"server-url","value":"https://'$rancher_server_ip'"}' --insecure)

# Create cluster
CLUSTERRESPONSE=$(docker run --net host \
    --rm \
    $curl_prefix/curl \
     -s 'https://127.0.0.1/v3/cluster' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" \
     --data-binary "{\"type\":\"cluster\",\"rancherKubernetesEngineConfig\":{\"ignoreDockerVersion\":false,\"sshAgentAuth\":false,\"type\":\"rancherKubernetesEngineConfig\",\"kubernetesVersion\":\"$kubernetes_version\",\"authentication\":{\"type\":\"authnConfig\",\"strategy\":\"x509\"},\"network\":{\"type\":\"networkConfig\",\"plugin\":\"flannel\",\"flannelNetworkProvider\":{\"iface\":\"eth1\"},\"calicoNetworkProvider\":null},\"ingress\":{\"type\":\"ingressConfig\",\"provider\":\"nginx\"},\"services\":{\"type\":\"rkeConfigServices\",\"kubeApi\":{\"podSecurityPolicy\":false,\"type\":\"kubeAPIService\"},\"etcd\":{\"type\":\"etcdService\",\"extraArgs\":{\"heartbeat-interval\":500,\"election-timeout\":5000}}}},\"name\":\"quickstart\"}" --insecure)

# Extract clusterid to use for generating the docker run command
CLUSTERID=`echo $CLUSTERRESPONSE | jq -r .id`

# Generate cluster registration token
CLUSTERREGTOKEN=$(docker run --net=host \
    --rm \
    $curl_prefix/curl \
     -s 'https://127.0.0.1/v3/clusterregistrationtoken' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" --data-binary '{"type":"clusterRegistrationToken","clusterId":"'$CLUSTERID'"}' --insecure)
