#!/bin/bash
# Setup Jenkins Project
if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "  $0 GUID REPO CLUSTER"
    echo "  Example: $0 wkha https://github.com/redhat-gpte-devopsautomation/advdev_homework_template.git na311.openshift.opentlc.com"
    exit 1
fi

GUID=$1
REPO=$2
CLUSTER=$3
echo "Setting up Jenkins in project ${GUID}-jenkins from Git Repo ${REPO} for Cluster ${CLUSTER}"

# Set up Jenkins with sufficient resources
oc new-app jenkins-persistent --param ENABLE_OAUTH=true --param MEMORY_LIMIT=2Gi --param VOLUME_CAPACITY=4Gi --param DISABLE_ADMINISTRATIVE_MONITORS=true -n ${GUID}-jenkins
oc set resources dc jenkins --limits=memory=2Gi,cpu=2 --requests=memory=1Gi,cpu=500m -n ${GUID}-jenkins

# Create custom agent container image with skopeo
oc new-build -D $'FROM docker.io/openshift/jenkins-agent-maven-35-centos7:v3.11\nUSER root\nRUN yum -y install skopeo && yum clean all\nUSER 1001' --name=jenkins-agent-appdev -n ${GUID}-jenkins
oc get is -n ${GUID}-jenkins

# Make sure that Jenkins is fully up and running before proceeding!
while : ; do
  echo "Checking if Jenkins is Ready..."
  AVAILABLE_REPLICAS=$(oc get dc jenkins -n ${GUID}-jenkins -o=jsonpath='{.status.availableReplicas}')
  if [[ "$AVAILABLE_REPLICAS" == "1" ]]; then
    echo "...Yes. Jenkins is ready."
    break
  fi
  echo "...no. Sleeping 10 seconds."
  sleep 10
done

# Create pipeline build config pointing to the ${REPO} with contextDir `openshift-tasks`
oc project ${GUID}-jenkins
echo 'kind: "BuildConfig"
apiVersion: "v1"
metadata:
   name: "tasks-pipeline"
spec:
   source:
      type: "Git"
      git:
         uri: "https://github.com/tripathisushil/ox.git"
   strategy:
      type: "JenkinsPipeline"
      jenkinsPipelineStrategy:
         jenkinsfilePath: openshift-tasks/Jenkinsfile' | oc create -f - -n ${GUID}-jenkins
oc start-build tasks-pipeline -n ${GUID}-jenkins
