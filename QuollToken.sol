// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "./Interfaces/IQuollToken.sol";

contract QuollToken is IQuollToken, ERC20Upgradeable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    mapping(address => bool) public access;

    uint256 public maxSupply;
    uint256 public totalCliffs;
    uint256 public reductionPerCliff;

    // --- Events ---
    event AccessUpdated(address _operator, bool _access);

    function initialize() public initializer {
        __Ownable_init();

        __ERC20_init_unchained("Quoll Token", "QUO");

        access[msg.sender] = true;

        maxSupply = 100 * 1000000 * 1e18; //100mil
        totalCliffs = 1000;
        reductionPerCliff = maxSupply.div(totalCliffs);

        emit AccessUpdated(msg.sender, true);
    }

    function setAccess(address _operator, bool _access) external onlyOwner {
        access[_operator] = _access;

        emit AccessUpdated(_operator, _access);
    }

    function mint(address _to, uint256 _amount) external override {
        require(access[msg.sender], "!auth");

        uint256 supply = totalSupply();
        if (supply == 0) {
            //premine, one time only
            _mint(_to, _amount);
            return;
        }

        //use current supply to gauge cliff
        //this will cause a bit of overflow into the next cliff range
        //but should be within reasonable levels.
        //requires a max supply check though
        uint256 cliff = supply.div(reductionPerCliff);
        //mint if below total cliffs
        if (cliff < totalCliffs) {
            //for reduction% take inverse of current cliff
            uint256 reduction = totalCliffs.sub(cliff);
            //reduce
            _amount = _amount.mul(reduction).div(totalCliffs);

            //supply cap check
            uint256 amtTillMax = maxSupply.sub(supply);
            if (_amount > amtTillMax) {
                _amount = amtTillMax;
            }

            //mint
            _mint(_to, _amount);
        }
    }
}
