#!/bin/bash
# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Ensure current user is the owner for all files
mkdir ora2pg/data/
sudo chown -R $USER:$USER .

# Enable All Services Required
gcloud services enable \
  storage.googleapis.com \
  dataflow.googleapis.com \
  datastream.googleapis.com \
  compute.googleapis.com \
  sqladmin.googleapis.com \
  servicenetworking.googleapis.com \
  pubsub.googleapis.com \
  --project=${PROJECT_ID}

# Create GCS Bucket
gcloud storage buckets create ${GCS_BUCKET} --project=${PROJECT_NUMBER}

# Deploy CloudSQL Instance
SQL_INSTANCE=$(gcloud sql instances list --project=${PROJECT_ID} | grep "${CLOUD_SQL}")
if [ "${SQL_INSTANCE}" == "" ]
then
    gcloud compute addresses create google-managed-services-postgres \
          --global --purpose=VPC_PEERING \
          --prefix-length=16 --network=default \
          --project=${PROJECT_ID}
    gcloud services vpc-peerings connect \
          --service=servicenetworking.googleapis.com \
          --ranges=google-managed-services-postgres \
          --network=default \
          --project=${PROJECT_ID}
    gcloud beta sql instances create ${CLOUD_SQL} \
        --database-version=POSTGRES_11 \
        --cpu=4 --memory=3840MiB \
        --region=${REGION} \
        --no-assign-ip \
        --network=default \
        --root-password=${DATABASE_PASSWORD} \
        --project=${PROJECT_ID}
else
    echo "CloudSQL Instance Exists"
    echo ${SQL_INSTANCE}
fi

SERVICE_ACCOUNT=$(gcloud sql instances describe ${CLOUD_SQL} --project=${PROJECT_ID} | grep 'serviceAccountEmailAddress' | awk '{print $2;}')
# Note: Migrating scripts using gsutil iam ch is more complex than get or set. You need to replace the single iam ch command with a series of gcloud storage bucket add-iam-policy-binding and/or gcloud storage bucket remove-iam-policy-binding commands, or replicate the read-modify-write loop.
# Note: gsutil iam ch does not support modifying IAM policies that contain conditions. gcloud storage commands do support conditions.
gcloud storage buckets add-iam-policy-binding ${GCS_BUCKET} --member="serviceAccount:${SERVICE_ACCOUNT}" --role="objectViewer"

# Create Pub/Sub Resources for GCS Notifications
TOPIC_EXISTS=$(gcloud pubsub topics list --project=${PROJECT_ID} | grep ${PUBSUB_TOPIC})
if [ "${TOPIC_EXISTS}" == "" ]
then
  echo "Deploying Pub/Sub Resources"
  gcloud pubsub topics create ${PUBSUB_TOPIC} --project=${PROJECT_ID}

  gcloud pubsub subscriptions create ${PUBSUB_SUBSCRIPTION} \
  --topic=${PUBSUB_TOPIC} --project=${PROJECT_ID}

  gcloud storage buckets notifications create "${GCS_BUCKET}" --payload-format="json" --object-prefix="${DATASTREAM_ROOT_PATH}" --topic="${PUBSUB_TOPIC}"
fi
