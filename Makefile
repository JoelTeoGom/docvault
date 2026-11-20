EMULATOR_HOME := $(HOME)/.aws/emulator
FUNCTIONS := api worker
LOCAL_ENV := . ./local/env.sh &&
STATE_BUCKET := docvault-tfstate

.PHONY: build emulator emulator-stop infra-local

build:
	for function in $(FUNCTIONS); do \
		GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -tags lambda.norpc -trimpath -ldflags="-s -w -buildid=" \
			-o build/$$function/bootstrap ./cmd/$$function || exit 1; \
		touch -t 202001010000 build/$$function/bootstrap; \
		rm -f build/$$function.zip; \
		(cd build/$$function && zip -qX ../$$function.zip bootstrap) || exit 1; \
	done

emulator:
	docker build -t docvault-emulator local/emulator
	docker run -d --rm --name docvault-emulator --memory=2g \
		-p 127.0.0.1:9297:9297 \
		-e HOME=$(HOME) -v $(EMULATOR_HOME):$(EMULATOR_HOME) \
		docvault-emulator -p 9297 --telemetry off

emulator-stop:
	docker stop docvault-emulator

infra-local: build
	$(LOCAL_ENV) aws s3api head-bucket --bucket $(STATE_BUCKET) 2>/dev/null || ( \
		$(LOCAL_ENV) aws s3api create-bucket --bucket $(STATE_BUCKET) \
			--create-bucket-configuration LocationConstraint=eu-west-1 >/dev/null && \
		$(LOCAL_ENV) aws s3api put-bucket-versioning --bucket $(STATE_BUCKET) \
			--versioning-configuration Status=Enabled )
	$(LOCAL_ENV) terraform -chdir=infra init -reconfigure -backend-config=../local/backend.hcl
	$(LOCAL_ENV) terraform -chdir=infra apply
