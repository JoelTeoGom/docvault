unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE

export AWS_ENDPOINT_URL=https://127.0.0.1:9297
export AWS_SHARED_CREDENTIALS_FILE=$HOME/.aws/emulator/9297/emulator_credentials
export AWS_CONFIG_FILE=$HOME/.aws/emulator/9297/config
export AWS_CA_BUNDLE=$HOME/.aws/emulator/9297/ca.pem
export AWS_EC2_METADATA_DISABLED=true
export AWS_PAGER=""

export TF_WORKSPACE=local
export TF_VAR_s3_use_path_style=true
export TF_VAR_allowed_origins='["http://localhost:5173"]'
