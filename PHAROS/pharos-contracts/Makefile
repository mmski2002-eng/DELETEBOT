.PHONY: build
build:
	forge build --via-ir --extra-output storageLayout --force

.PHONY: check
check:
	make build

.PHONY: fmt
fmt:
	forge fmt

.PHONY: test
test:
	forge test --via-ir -vvv
