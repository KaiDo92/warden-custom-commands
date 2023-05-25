Magento 2 & Den (Warden) Setup
========================================================
Useful URLs on DEV:

* https://traefik.den.test/
* https://portainer.den.test/
* https://dnsmasq.den.test/
* https://mailhog.den.test/

## Developer Setup

### Prerequisites:

* [Docker Desktop](https://docs.docker.com/desktop/install/mac-install/) for Mac 2.2.0.0 or later
  or [Docker for Linux](https://docs.docker.com/get-docker/)
  or [Docker for Windows](https://docs.docker.com/desktop/install/windows-install/)
* [Homebrew](https://brew.sh/) is installed.
* [Den](https://swiftotter.github.io/den/index.html) 1.0.0 or later is installed. See
  the [Installing Den](https://swiftotter.github.io/den/installing.html) docs page for further info and procedures.

1. Install docker and docker-compose
    ```
    sudo apt-get update
    sudo apt-get install ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo service docker start
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.16.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    ```
2. Fix docker command permission
    ```
    sudo groupadd docker
    sudo usermod -aG docker $USER
    newgrp docker
    mkdir /home/"$USER"/.docker
    sudo chown "$USER":"$USER" /home/"$USER"/.docker -R
    sudo chmod g+rwx "$HOME/.docker" -R
    ```
3. Start docker on boot
    ```
    sudo systemctl enable docker.service
    sudo systemctl enable containerd.service
    ```
4. Install Homebrew
    ```
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    (echo; echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"') >> /home/$USER/.bashrc
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    ```
5. Install Den
    ```
    brew install gcc
    sudo apt-get install build-essential procps curl file git
    brew install swiftotter/den/den
    den svc up
    ```
6. Load the site in your browser using the links and credentials taken from the init script output.

   **Note:** If you are using **Firefox** and it warns you the SSL certificate is invalid/untrusted, go to
   Preferences -> Privacy & Security -> View Certificates (bottom of page) -> Authorities -> Import and
   select `~/.den/ssl/rootca/certs/ca.cert.pem` for import, then reload the page.

   **Note:** If you are using **Chrome** on **Linux** and it warns you the SSL certificate is invalid/untrusted, go to
   Chrome Settings -> Privacy And Security -> Manage Certificates (see more) -> Authorities -> Import and
   select `~/.den/ssl/rootca/certs/ca.cert.pem` for import, then reload the page.

7. Auto DNS resolution for all *.test domains in local environment
    ```
    sudo mkdir -p /etc/systemd/resolved.conf.d
    echo -e "[Resolve]\nDNS=127.0.0.1\nDomains=~test\n" | sudo tee /etc/systemd/resolved.conf.d/den.conf > /dev/null
    sudo systemctl restart systemd-resolved
    ```

### Initializing Environment

In the below examples `~/Work/htdocs/magentoden` is used as the path. Simply replace this with whatever path you will be
running this project from. It is recommended however to deploy the project locally to a case-sensitive volume.

1. Clone the project codebase.
    ```
    git clone -b develop git@github.com:<GITHUB_ACCOUNT>/<REPOSITORY_NAME>.git ~/Work/htdocs/magentoden
    ```
2. Change into the project directory.
    ```
    cd ~/Work/htdocs/magentoden
    ```

3. Create a new .env file in the project's root directory and ensure that you update the necessary variables accordingly (please refer to the .env.example file in this repository for guidance).

4. Run the init script to bootstrap the environment.
    ```
    den bootstrap
    ```

### Additional Configuration

Information on configuring and using tools such as Xdebug, LiveReload, MFTF, and multi-domain site setups may be found
in the Den docs page on [Configuration](https://swiftotter.github.io/den/configuration.html).

### Destroying Environment

To completely destroy the local environment we just created, run `den env down -v` to tear down the project’s Docker
containers, volumes, and (where applicable) cleanup the Mutagen sync session.

# Den Custom Commands

Provides additional commands to simplify local installation.

### Installation
Clone this repository in `~/.den/commands` to install it globally (recommended), or locally per project in `[project directory]/.den/commands`.

### Configuration
In the project `.env` (after `den env-init`), add and configure these values:

```
REMOTE_PROD_HOST=project.com
REMOTE_PROD_USER=user
REMOTE_PROD_PORT=22
REMOTE_PROD_PATH=/var/www/html

REMOTE_STAGING_HOST=staging.project.com
REMOTE_STAGING_USER=user
REMOTE_STAGING_PORT=22
REMOTE_STAGING_PATH=/var/www/html

REMOTE_DEV_HOST=dev.project.com
REMOTE_DEV_USER=user
REMOTE_DEV_PORT=22
REMOTE_DEV_PATH=/var/www/html
```

#### Adobe Commerce Cloud
The `REMOTE_[env]_HOST` variables must be set with the name of the environment. All other variables are not used and can be removed.

Additionally, you must have this variable:  
`CLOUD_PROJECT=[projectId]`

### Usage

For all commands, execute `den <command> -h` to see the details of all options.

`den bootstrap`
* Create and configure Den environment
* Download and import database dump from selected remote
* Download medias from selected remote
* Install composer dependencies
* Configure Redis, Varnish and ElasticSearch if applicable
* Other Magento config like domain, switch some payment methods to sandbox
* Create admin user

`den db-dump`
* Dump DB from selected remote

`den import-db`
* Import DB. File **must** be specified with option `--file`

`den sync-media`
* Download medias from selected remote
* Product images are not downloaded by default (use `--include-product`)

`den open`
* Open DB tunnel to local or remote environments
* SSH to local or remote environments
* Show SFTP link you can use in your SFTP client
