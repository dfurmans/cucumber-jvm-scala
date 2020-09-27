SHELL := /usr/bin/env bash

default:
	mvn clean install
.PHONY: default

VERSION = $(shell mvn help:evaluate -Dexpression=project.version -q -DforceStdout 2> /dev/null)
NEW_VERSION = $(subst -SNAPSHOT,,$(VERSION))
CURRENT_BRANCH = $(shell git rev-parse --abbrev-ref HEAD)

clean:
	mvn clean release:clean
.PHONY: clean

version:
	@echo ""
	@echo "The next version of Cucumber-Scala will be $(NEW_VERSION) and released from '$(CURRENT_BRANCH)'"
	@echo ""
.PHONY: version

update-compatibility:
	MSG_VERSION=$$(mvn help:evaluate -Dexpression=messages.version -q -DforceStdout 2> /dev/null) && \
	git clone --branch messages/v$$MSG_VERSION git@github.com:cucumber/cucumber.git target/cucumber
	rm -rf compatibility/src/test/resources/*
	cp -r target/cucumber/compatibility-kit/javascript/features compatibility/src/test/resources
	rm -rf target/cucumber
.PHONY: update-compatibility

update-dependency-versions:
	mvn versions:force-releases
	mvn versions:update-properties -DallowMajorUpdates=false -Dmaven.version.rules="file://`pwd`/.m2/maven-version-rules.xml"
.PHONY: update-dependency-versions

update-major-dependency-versions:
	mvn versions:force-releases
	mvn versions:update-properties -DallowMajorUpdates=true -Dmaven.version.rules="file://`pwd`/.m2/maven-version-rules.xml"
.PHONY: update-major-dependency-versions

update-installdoc:
	cat docs/install.md | ./scripts/update-install-doc.sh $(NEW_VERSION) > docs/install.md.tmp
	mv docs/install.md.tmp docs/install.md
.PHONY: update-installdoc

update-changelog:
	cat CHANGELOG.md | ./scripts/update-changelog.sh $(NEW_VERSION) > CHANGELOG.md.tmp
	mv CHANGELOG.md.tmp CHANGELOG.md
.PHONY: update-changelog

.commit-and-push-changelog-and-docs:
	git commit -am "Update CHANGELOG and docs for v$(NEW_VERSION)"
	git push
.PHONY: .commit-and-push-changelog

.release-in-docker: default update-changelog update-installdoc .commit-and-push-changelog-and-docs
	[ -f '/home/cukebot/import-gpg-key.sh' ] && /home/cukebot/import-gpg-key.sh
	mvn --batch-mode release:clean release:prepare -DautoVersionSubmodules=true -Darguments="-DskipTests=true -DskipITs=true -Darchetype.test.skip=true"
	git checkout "v$(NEW_VERSION)"
	mvn deploy -P-examples -P-compatibility -Psign-source-javadoc -DskipTests=true -DskipITs=true -Darchetype.test.skip=true
	git checkout $(CURRENT_BRANCH)
	git fetch
.PHONY: release-in-docker

release:
	[ -d '../secrets' ]  || git clone keybase://team/cucumberbdd/secrets ../secrets
	git -C ../secrets pull
	../secrets/update_permissions
	docker pull cucumber/cucumber-build:latest
	docker run \
	  --volume "${shell pwd}":/app \
	  --volume "${shell pwd}/../secrets/import-gpg-key.sh":/home/cukebot/import-gpg-key.sh \
	  --volume "${shell pwd}/../secrets/codesigning.key":/home/cukebot/codesigning.key \
	  --volume "${shell pwd}/../secrets/.ssh":/home/cukebot/.ssh \
	  --volume "${HOME}/.m2"/repository:/home/cukebot/.m2/repository \
	  --volume "${HOME}/.gitconfig":/home/cukebot/.gitconfig \
	  --env-file ../secrets/secrets.list \
	  --user 1000 \
	  --rm \
	  -it cucumber/cucumber-build:latest \
	  make .release-in-docker
.PHONY: release

