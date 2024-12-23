#!/bin/bash

echo $1 

#docker run --rm \
#   -v /var/run/docker.sock:/var/run/docker.sock \
#    -v $WORKSPACE:/root/.cache/ \
#    aquasec/trivy:0.57.1 -q \
#    image --exit-code 0 --severity HIGH --light --compliance docker-cis-1.6.0 \
#    $1 

#docker run --rm \
#    -v /var/run/docker.sock:/var/run/docker.sock \
#    -v $WORKSPACE:/root/.cache/ \
#    aquasec/trivy:0.57.1 -q \
#    image --exit-code 1 --severity CRITICAL --light --compliance docker-cis-1.6.0 \
 #   $1

trivy image -f json -o trivy-docker-cis.json --severity HIGH,CRITICAL --exit-code 1 --compliance docker-cis-1.6.0 $1

exit_code=$?

                                        
if [[ $exit_code -eq 1 ]]; then
    echo "Image scanning failed. HIGH or CRITICAL vulnerabilities found."
    exit 1
else
    echo "Image scanning passed. No HIGH or CRITICAL vulnerabilities found."
fi