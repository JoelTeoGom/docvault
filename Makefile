EMULATOR_HOME := $(HOME)/.aws/emulator

.PHONY: emulator emulator-stop

emulator:
	docker build -t pdfbox-emulator local/emulator
	docker run -d --rm --name pdfbox-emulator --memory=2g \
		-p 127.0.0.1:9297:9297 \
		-e HOME=$(HOME) -v $(EMULATOR_HOME):$(EMULATOR_HOME) \
		pdfbox-emulator -p 9297 --telemetry off

emulator-stop:
	docker stop pdfbox-emulator
