FROM kbase/kb_perl:latest
# This container is intended to be a slightly updated version of sdkbase, usable for
# all support KB-SDK languages. It is currently built as a concatenation of the
# existing set of language specific base images as of Feb 2018
#
# Because the perl base image has trouble when built from scratch, we start with a
# snapshot of it as the sdkbase base image
# These ARGs values are passed in via the docker build command
ARG BUILD_DATE
ARG VCS_REF
ARG BRANCH=develop

# Some common packages that are useful
RUN apt-get update -y \
	&& apt-get install -y apt-transport-https ca-certificates make software-properties-common \
    	git apt-utils bzip2 unzip xz-utils ant rsync curl

# Next lets bring in the Java runtime from the openjdk:8-jdk dockerfile
RUN apt-get install -y --no-install-recommends \
		bzip2 \
		unzip \
		xz-utils
# Default to UTF-8 file.encoding
ENV LANG C.UTF-8

# add a simple script that can auto-detect the appropriate JAVA_HOME value
# based on whether the JDK or only the JRE is installed
RUN { \
		echo '#!/bin/sh'; \
		echo 'set -e'; \
		echo; \
		echo 'dirname "$(dirname "$(readlink -f "$(which javac || which java)")")"'; \
	} > /usr/local/bin/docker-java-home \
	&& chmod +x /usr/local/bin/docker-java-home

# do some fancy footwork to create a JAVA_HOME that's cross-architecture-safe
RUN ln -svT "/usr/lib/jvm/java-8-openjdk-$(dpkg --print-architecture)" /docker-java-home
ENV JAVA_HOME /docker-java-home

ENV JAVA_VERSION 8u151
ENV JAVA_DEBIAN_VERSION 8u151-b12-1~deb9u1

# see https://bugs.debian.org/775775
# and https://github.com/docker-library/java/issues/19#issuecomment-70546872
ENV CA_CERTIFICATES_JAVA_VERSION 20170531+nmu1

RUN set -ex; \
	\
# deal with slim variants not having man page directories (which causes "update-alternatives" to fail)
	if [ ! -d /usr/share/man/man1 ]; then \
		mkdir -p /usr/share/man/man1; \
	fi; \
	\
	apt-get install -y \
		openjdk-8-jdk-headless="$JAVA_DEBIAN_VERSION" \
		ca-certificates-java="$CA_CERTIFICATES_JAVA_VERSION" \
	; \
	# verify that "docker-java-home" returns what we expect
	[ "$(readlink -f "$JAVA_HOME")" = "$(docker-java-home)" ]; \
	\
# update-alternatives so that future installs of other OpenJDK versions don't change /usr/bin/java
	update-alternatives --get-selections | awk -v home="$(readlink -f "$JAVA_HOME")" 'index($3, home) == 1 { $2 = "manual"; print | "update-alternatives --set-selections" }'; \
# ... and verify that it actually worked for one of the alternatives we care about
	update-alternatives --query java | grep -q 'Status: manual'

# Install various servers by default
RUN apt-get install -y jetty9 uwsgi 
ENV JETTY_HOME /usr/share/jetty9

# Python support
RUN apt-get install -y python-dev libssl-dev python3-minimal python3-pip \
    && pip install pyopenssl ndg-httpsclient pyasn1 pyyaml gitpython \
    && pip install requests --upgrade \
    && pip install requests_toolbelt --upgrade \
    && pip install 'requests[security]' --upgrade \
    && pip install coverage nose2 nose \
	&& pip install --upgrade sphinx \
	&& pip install wsgiref jsonrpcbase biopython \
	&& pip3 install jsonrpcbase biopython

# Docker support
#RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
#	&& add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu xenial stable" \
#	&& apt-get update \
#	&& apt-get install -y docker-ce

# The Debian phantomjs is a little wonky and needs to have this set to run headless
#ENV QT_QPA_PLATFORM=offscreen

# Install kb-sdk in the image
RUN mkdir /root/src \
	&& cd /root/src \
	&& git clone https://github.com/kbase/kb_sdk.git \
	&& cd kb_sdk \
	&& make

# Setup some legacy directories and files
RUN mkdir -p /kb/deployment/lib /kb/deployment/lib
COPY user-env.sh /kb/deployment/user-env.sh

# Setup support libraries
RUN cd /tmp \
	&& git clone https://github.com/kbase/workspace_deluxe \
	&& cd workspace_deluxe \
	&& cp -vr lib/* /kb/deployment/lib/ \
	&& cd /tmp \
	&& git clone https://github.com/kbase/auth \
	&& cd auth \
	&& cp -vr python-libs/biokbase /kb/deployment/lib/ \
	&& cp -vr Bio-KBase-Auth/lib/Bio /kb/deployment/lib/ \
	&& cd ~/src/kb_sdk \
	&& cp -vr lib/biokbase /kb/deployment/lib/ \
	&& cp -vr lib/Bio /kb/deployment/lib/ \
	&& rm -rf /tmp/*
	
ENV PATH=$PATH:/root/src/kb_sdk/bin
ENV PERL5LIB=/kb/deployment/lib

# The BUILD_DATE value seem to bust the docker cache when the timestamp changes, move to
# the end
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-url="https://github.com/kbase/sdkbase.git" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.schema-version="1.0.0-rc1" \
      us.kbase.vcs-branch=$BRANCH \
      maintainer="Steve Chan sychan@lbl.gov"
      
