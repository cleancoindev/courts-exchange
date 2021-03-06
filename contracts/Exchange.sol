pragma solidity 0.4.24;
// pragma experimental ABIEncoderV2;

import "@aragon/os/contracts/lib/math/SafeMath.sol";
import './ABDKMath64x64.sol';
import './IERC20.sol';
import '../rewardcourts/contracts/IERC1155.sol';
import '../rewardcourts/contracts/RewardCourts.sol';

contract Exchange {
    using SafeMath for uint256;
    using ABDKMath64x64 for int128;

    enum TokenType { ERC20, ERC1155, REWARD_COURTS }

    struct Token {
        TokenType tokenType;
        address contractAddress;
        uint256 token;
    }

    function tokenHash(Token token) public pure returns (uint256) {
        if (token.tokenType == TokenType.ERC20) {
            return uint256(keccak256(token.tokenType, token.contractAddress));
        } else {
            return uint256(keccak256(token.tokenType, token.contractAddress, token.token));
        }
    }

    // token hash => value (ABDKMath fixed point)
    mapping (uint256 => int128) public rates;

    // token hash => limit
    mapping (uint256 => uint256) public limits;

    Token[] public allTokens; // TODO: retrieval of this

    function setAllTokenRates(Token[] _tokens, int128[] _rates) external {
        for (uint i = 0; i < allTokens.length; ++i) {
            uint256 hash = tokenHash(_tokens[i]);
            limits[hash] = 0; // "nullify" old tokens
        }
        allTokens = _tokens;
        for (uint j = 0; j < _tokens.length; ++j) {
            uint256 hash2 = tokenHash(_tokens[j]);
            rates[hash2] = _rates[j];
        }
    }

    function setTokenLimit(Token token, uint256 _limit) external {
        uint256 hash = tokenHash(token);
        limits[hash] = _limit;
    }

    function addToTokenLimit(Token token, uint256 _limit) external {
        uint256 hash = tokenHash(token);
        limits[hash] = limits[hash].add(_limit);
    }

    function setTokenLimits(Token[] _tokens, uint256[] _limits) external {
        for (uint j = 0; j < _tokens.length; ++j) {
            uint256 hash = tokenHash(_tokens[j]);
            limits[hash] = _limits[j];
        }
    }

    function addToTokenLimits(Token[] _tokens, uint256[] _limits) external {
        for (uint j = 0; j < _tokens.length; ++j) {
            uint256 hash = tokenHash(_tokens[j]);
            limits[hash] = limits[hash].add(_limits[j]);
        }
    }

    function exchange(Token _from, Token _to, uint256 _fromAmount, bytes _data) external {
        uint256 _fromHash = tokenHash(_from);
        uint256 _toHash = tokenHash(_to);
        int128 rate = rates[_toHash].divi(rates[_fromHash]);
        uint256 _toAmount = rate.mulu(_fromAmount);

        limits[_toHash] = limits[_toHash].sub(_toAmount);

        if (_from.tokenType == TokenType.ERC20) {
            IERC20(_from.contractAddress).transferFrom(msg.sender, this, _fromAmount);
        } else {
            IERC1155(_from.contractAddress).safeTransferFrom(msg.sender, this, _from.token, _fromAmount, _data);
        }

        if (_to.tokenType == TokenType.ERC20) {
            IERC20(_to.contractAddress).transferFrom(this, msg.sender, _toAmount);
        } else if (_to.tokenType == TokenType.ERC1155) {
            IERC1155(_to.contractAddress).safeTransferFrom(this, msg.sender, _to.token, _toAmount, _data);
        } else /*if (_to.tokenType == TokenType.REWARD_COURTS)*/ {
            uint128[] memory _courtsPath = new uint128[](0);
            RewardCourts(_to.contractAddress).mint(msg.sender, _to.token, _toAmount, _data, _courtsPath);
        }
    }
}