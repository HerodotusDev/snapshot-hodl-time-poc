# Snapshot <> Herodotus DP -- Proof of Concept

## 1. Build

Build the compiled contract class file:

```console
scarb build
```

You should see that a new build file has been added:

```
custom_module \
    src \
       lib.cairo
    target \
       dev \
          custom_module_custom_module.compiled_contract_class.json
```

## 2. Upload

Upload the compiled contract class file to the program registry:

```console
curl --location 'https://sharp.api.herodotus.cloud/submit-program?apiKey={API_KEY}' \
--form 'programFile=@"custom_module_custom_module.compiled_contract_class.json"'
```

This request will return a program hash as a response:

```console
0xaae117f9cdfa4fa4d004f84495c942adebf17f24aec8f86e5e6ea29956b47e
```

To comfirm if the program is registered, you can query the program registry:

```sh
curl --location 'http://program-registery.api.herodotus.cloud/get-metadata?program_hash=0xaae117f9cdfa4fa4d004f84495c942adebf17f24aec8f86e5e6ea29956b47e'
```

## 3. Request

Now, with this custom module, you can submit a request to the HDP:

Provide the correct program hash from the program registry. Input data should be the input for the `pub fn main()` function.

Note that values belows are examples and should be replaced with the correct input values.

```console
curl --location 'https://hdp.api.herodotus.cloud/submit-batch-query?apiKey={API_KEY}' \
--header 'Content-Type: application/json' \
--data '{
  "destinationChainId": "ETHEREUM_SEPOLIA",
  "tasks": [
    {
      "type": "Module",
      "programHash": "0xaae117f9cdfa4fa4d004f84495c942adebf17f24aec8f86e5e6ea29956b47e",
      "inputs": [
        {
          "visibility": "public",
          "value": "0x3"
        },
        {
          "visibility": "public",
          "value": "0x5222A4"
        },
        {
          "visibility": "public",
          "value": "0x5222A7"
        },
        {
          "visibility": "public",
          "value": "0x5222C4"
        },
        {
          "visibility": "public",
          "value": "0x13cb6ae34a13a0977f4d7101ebc24b87bb23f0d5"
        }
      ]
    }
  ]
}'
```
