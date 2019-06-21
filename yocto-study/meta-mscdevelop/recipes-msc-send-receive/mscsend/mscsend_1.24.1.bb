# yocto-bsp-filename {{=example_recipe_name}}_0.1.bb
#
# This file was derived from the 'Hello World!' example recipe in the
# Yocto Project Development Manual.
#

SUMMARY = "Simple helloworld application"
SECTION = "examples"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS += "kern-tools-native"

# the GPL is version 2 only
# LICENSE = "GPLv2 & bzip2"
# LIC_FILES_CHKSUM = "file://LICENSE;md5=de10de48642ab74318e893a61105afbb"

SRC_URI = "git://git@github.com/guolibao/myrepo.git;protocol=ssh \
           file://mscsend.c \
"

SRCREV="master"

S = "${WORKDIR}"

do_compile() {
	     ${CC} mscsend.c -o mscsend
}

do_install() {
	     install -d ${D}${bindir}
	     install -m 0755 mscsend ${D}${bindir}
}

# to execute the recipe, use bitbake -c mscsend, not bitbake mscsend