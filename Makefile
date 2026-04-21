.PHONY: build clean up destroy ssh

build:
	sudo ./build-bundle.sh && mv genesis*.tar.gz bundles/

clean:
	@sudo rm -rf bundles/*
	@sudo rm -rf genesis*/

up:
	@cd bundles && for t in genesis-*.tar.gz; do [ -f "$$t" ] && tar -xzvf "$$t" --skip-old-files; done
	@vagrant up

destroy:
	@vagrant destroy -f

ssh:
	@vagrant ssh
