#!/bin/bash
echo "################################################"
GCP_PROJECT_ID=$(gcloud config get-value project)

export GCS_BUCKET_PATH="${GCP_PROJECT_ID}-bucket/eventdata"
echo "   GCS_BUCKET_PATH : $GCS_BUCKET_PATH"

gsutil cp -r gs://${GCS_BUCKET_PATH}/* .
python3 update_event_time.py

echo "eventdata has uploaded"
echo "################################################"