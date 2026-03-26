# Script to mergue firmware

## Started

Use Linux or WSL (for Windows)

Install dependencies

```bash
sudo apt install unzip lz4 liblz4-dev
```

## How use

- First put **beta.zip** in beta folder and **firmware (.zip/.tar/.md5)** in original folder.
- Second run **automate.sh**:

  ```bash
  ./automate.sh
  ```

- Wait finish script.
- The .img updates stay in out/ folder.

## Credits

- <a href="https://github.com/erfanoabdi">erfanoabdi</a> for BlockImageVerify and BlockImageUpdate binary
