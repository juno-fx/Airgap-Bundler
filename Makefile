.PHONY: build clean lint test

build:
	./build-bundle.sh

clean:
	rm -f airgap-bundle*.tar.gz
	rm -rf airgap-bundle*/
	rm -rf .test-integration/

lint:
	devbox run -- shellcheck build-bundle.sh test-integration.sh

test:
	./test-integration.sh
