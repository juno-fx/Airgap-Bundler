.PHONY: build clean lint test up rsync ssh halt destroy status airgap online

build:
	./build-bundle.sh && mv genesis*.tar.gz bundles/

clean:
	rm -f bundles/genesis*.tar.gz
	rm -rf genesis*/
	rm -rf .test-integration/

lint:
	shellcheck -e SC2001 build-bundle.sh test-integration.sh update_dns.sh

test:
	./test-integration.sh

up: provision airgap

provision:
	@vagrant up

ssh:
	@vagrant ssh

halt:
	@vagrant halt

destroy:
	@vagrant destroy -f

status:
	@vagrant status

airgap: halt
	@VBoxManage modifyvm airgap-vm --cable-connected1 off
	@vagrant up --no-provision &
	@echo "NAT cable disconnected. VM internet access blocked."

online: halt
	@VBoxManage modifyvm airgap-vm --cable-connected1 on
	@vagrant up --no-provision &
	@echo "NAT cable reconnected. VM internet access enabled."