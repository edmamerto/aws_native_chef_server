#!/bin/bash -x

# Provided variables that are required: STACKNAME, BUCKET, AWS_REGION

# Determine if we are the bootstrap node
INSTANCE_ID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`
BOOTSTRAP_TAGS=`aws ec2 describe-tags --region $AWS_REGION --filter "Name=resource-id,Values=$INSTANCE_ID" --output=text | grep BootstrapAutoScaleGroup`

# Check if the configs already exist
CONFIGS_EXIST=`aws s3 sync s3://${BUCKET}/${STACKNAME}/ | grep migration-level`

download_config () {
  aws s3 sync s3://${BUCKET}/${STACKNAME}/etc_opscode /etc/opscode
  mkdir -p /var/opt/opscode/upgrades
  touch /var/opt/opscode/bootstrapped
  aws s3 cp s3://${BUCKET}/${STACKNAME}/migration-level /var/opt/opscode/upgrades/
}

upload_config () {
  aws s3 sync /etc/opscode s3://${BUCKET}/${STACKNAME}/etc_opscode
  aws s3 cp /var/opt/opscode/upgrades/migration-level s3://${BUCKET}/${STACKNAME}/
}

server_reconfigure () {
  chef-server-ctl reconfigure --accept-license
  chef-manage-ctl reconfigure --accept-license
}

server_upgrade () {
  chef-server-ctl upgrade --accept-license
  chef-server-ctl start
  chef-manage-ctl reconfigure --accept-license
}

# Here we go

# If we're not bootstrap OR a config already exists, sync down the rest of the secrets first before reconfiguring
if [ -z "${BOOTSTRAP_TAGS}" ] || [ -n "${CONFIGS_EXIST}" ] ; then
  echo "[INFO] configuring this node as a regular Chef frontend or restoring a Bootstrap"
  download_config
else
  echo "[INFO] configuring this node as a Bootstrap Chef frontend"
fi

# Upgrade/Configure handler
# If we're a bootstrap and configs already existed, upgrade
if [ -n "${BOOTSTRAP_TAGS}" ] || [ -n "${CONFIGS_EXIST}" ] ; then
  echo "[INFO] Looks like we're on a boostrap node that may need to be upgraded"
  server_upgrade
else
  echo "[INFO] Running chef-server-ctl reconfigure"
  server_reconfigure
fi

# the bootstrap instance should sync files after reconfigure, regardless if configs exist or not (upgrades)
if [ -n "${BOOTSTRAP_TAGS}" ]; then
  echo "[INFO] syncing bootstrap secrets up to S3"
  upload_config
fi
