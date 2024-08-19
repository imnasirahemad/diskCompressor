# Step-by-Step Installation Guide

This is a step-by-step guide to setting up a compressed device using LZ4 compression on a Linux system. The guide also covers the creation of the ext4 volume image.

## Step 1: Prerequisites

* Ensure you have a Linux system with a compatible package manager (apt-get or yum).
* Download the required files:
	+ `docker-compose.yml`
	+ `testNow.sh`
	+ `ext4_volume.img`

## Step 2: Create the ext4 Volume Image

1. Create a new directory for your project and navigate to it in the terminal.
2. Run the command `dd if=/dev/zero of=ext4_volume.img bs=1M count=100` to create a 100MB file.
3. Run the command `mkfs.ext4 ext4_volume.img` to create an ext4 file system on the image.

## Step 3: Create a Docker Environment

1. Install Docker on your system if you haven't already.
2. Create a new directory for your project and navigate to it in the terminal.
3. Copy the `docker-compose.yml` file into this directory.
4. Run the command `docker-compose up -d` to create a Docker container in detached mode.

## Step 4: Prepare the Container

1. Run the command `docker-compose exec ubuntu bash` to enter the container.
2. Update the package list by running `apt-get update`.
3. Install the necessary dependencies by running `apt-get install -y util-linux e2fsprogs lz4`.
4. Create a mount point for the ext4 volume by running `mkdir -p /mnt/ext4_volume`.
5. Mount the ext4 volume by running `mount -o loop /ext4_volume.img /mnt/ext4_volume`.

## Step 5: Run the Setup Script

1. Copy the `testNow.sh` script into the container by running `docker-compose cp testNow.sh ubuntu:/testNow.sh`.
2. Make the script executable by running `chmod +x /testNow.sh`.
3. Run the script by executing `/testNow.sh`.

## Step 6: Verify the Setup

1. Check the output of the script to ensure it completed successfully.
2. Verify that the compressed file has been created by running `ls /mnt/ext4_volume/compressed`.
3. Check the system-wide environment to ensure the LD_LIBRARY_PATH has been updated by running `echo $LD_LIBRARY_PATH`.

## Step 7: Clean Up

1. Exit the container by running `exit`.
2. Stop the Docker container by running `docker-compose stop`.
3. Remove the container by running `docker-compose rm`.

## Troubleshooting

* Ensure the script is run as root.
* Verify the package manager and OS detection.
* Check the installation of dependencies and LZ4.
* Verify the creation of the setup script and its execution.
* Review the system-wide environment updates.