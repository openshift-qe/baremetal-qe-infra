# fcos-base-image

The fcos-base-image definition is meant to be used for extending the fcos image and adding common tools 
and configurations shared by all the container-native OS images we will be building to run the BMaaS testing infrastructure 
for BareMetal OCP clusters testing.

## How to build the image

Use any tool capable of building OCI images, like buildah, podman or docker.

## How to use the image

Bootstrap a node with a fedora coreos boot image. Then, install coreos and set the users as reported in the 
[fedora documentation](https://docs.fedoraproject.org/en-US/fedora-coreos/bare-metal/).

After the reboot, you can rebase the OS to the fcos-base-image, executing as root:

```bash
rpm-ostree rebase ostree-unverified-registry:quay.io/org/fcos-base-image:latest --bypass-driver --reboot
```

## Structure of the image definition

The container image definition is stored at `Containerfile`. 

The `root/` folder is copied into the image rootfs, and contains the files required to configure the OS.

When possible, prefer not to change the `/etc` files, but the ones in `/usr/`. This is because the `/etc` files are
managed by rpm-ostree through a three-way merge, and any files modified by the user will not be updated by rpm-ostree
when the OS is updated.

The directories `/etc` and `/var` are mounted as read-write which lets users write and modify files.

The directory `/etc` may be changed by deployments, but will not override user made changes. 

The content under `/var` is left untouched by rpm-ostree when applying upgrades or rollbacks, 
don't use it to store Container image files.