# Prerequisites
- Ansible Core >= 2.13.7 and 2.14.1
- Python >= 3.9.6
- OpenManage Python Software Development Kit (OMSDK)

The OMSDK version installed with pip prevents the ansible module to work with disk controllers, install manually following instructions below

# Install OMSDK from github:

```
git clone https://github.com/dell/omsdk.git
cd omsdk
pip3 install -r requirements-python3x.txt
sh build.sh 1.2 503 (See package version on github)
cd dist
pip install omsdk-1.2.503-py2.py3-none-any.whl
```
