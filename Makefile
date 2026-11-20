EMULATOR_HOME := $(HOME)/.aws/emulator
FUNCTIONS := api worker

.PHONY: build emulator emulator-stop

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
