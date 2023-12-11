# AsyncSwapper Smart Contract

The AsyncSwapper smart contract allows users to swap ERC20 tokens using the 0x API. It acts as a middleware to interface with the 0x router contract.

## Usage

Before calling the swap function, users or frontends should first get a quote from the 0x API, which will return an object that includes the Ethereum transaction data.
This data is then passed to the swap function along with the other parameters.

Here is an example of how to get a quote from the 0x API:

```bash
curl --location --request GET 'https://api.0x.org/swap/v1/quote?buyToken=0x6B175474E89094C44Da98b954EedeAC495271d0F&sellToken=0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE&sellAmount=100000&excludedSources=Kyber' --header '0x-api-key: YOUR_API_KEY'
```

Please note: the user or contract should have enough balance of the sell token and should have approved the AsyncSwapper contract to spend the sell token on their behalf.
