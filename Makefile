.PHONY: build clean lint test

build:
	./build-bundle.sh

clean:
	rm -f airgap-bundle*.tar.gz
	rm -rf airgap-bundle*/
	rm -rf .test-integration/

lint:
	devbox run -- shellcheck -e SC2001 build-bundle.sh test-integration.sh update_dns.sh

test:
	./test-integration.sh
