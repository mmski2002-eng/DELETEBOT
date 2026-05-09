When the genesis block is generated, the staking contract is written directly as runtime code. Due to the lack of a standard initialization procedure, we will fill the following values into the genesis storage slots:
1. AccessControl: Write the administrator parameters.
```python
def _generate_access_control_admin(self, configs: Dict[str, str], account: Optional[str]):
        """
        struct RoleData {
        mapping(address account => bool) hasRole;
        bytes32 adminRole;
        }

        bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;


        /// @custom:storage-location erc7201:openzeppelin.storage.AccessControl
        struct AccessControlStorage {
            mapping(bytes32 role => RoleData) _roles;
        }

        // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.AccessControl")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 private constant AccessControlStorageLocation = 0x02dd7bc7dec4dceedda775e58dd541e08a116c6c53815c0bd028192f7b626800;

        function _getAccessControlStorage() private pure returns (AccessControlStorage storage $) {
            assembly {
                .slot := AccessControlStorageLocation
            }
        }

        function _grantRole(bytes32 role, address account) internal virtual returns (bool) {
            AccessControlStorage storage $ = _getAccessControlStorage();
            if (!hasRole(role, account)) {
                $._roles[role].hasRole[account] = true;
                emit RoleGranted(role, account, _msgSender());
                return true;
            } else {
                return false;
            }
        }
        """

        # either use admin_addr defined in `deploy.light.json`, or use the params
        if account is None:
            admin_addr = self._deploy.admin_addr
        else:
            admin_addr = account

        if admin_addr.startswith('0x'):
            admin_addr = admin_addr[2:]  # Remove the '0x' prefix


        access_control_storage_base_slot = "02dd7bc7dec4dceedda775e58dd541e08a116c6c53815c0bd028192f7b626800"
        access_control_storage_base_slot_bytes = bytes.fromhex(access_control_storage_base_slot).rjust(32, b'\0')
        default_admin_role_index = 0
        default_admin_role_index_bytes = int_to_big_endian(default_admin_role_index).rjust(32, b'\0')
        # now we have `RoleData` slot, i.e. `hasRole` field
        access_control_storage_default_admin_role_data_slot = keccak(default_admin_role_index_bytes + access_control_storage_base_slot_bytes)

        # get the account slot in `RoleData.hasRole` 
        admin_addr_bytes = bytes.fromhex(admin_addr).rjust(32, b'\0')
        admin_addr_slot = keccak(admin_addr_bytes + access_control_storage_default_admin_role_data_slot)
        # set the account role to true
        admin_addr_slot_value = 0x1
        admin_addr_slot_value_bytes = int_to_big_endian(admin_addr_slot_value).rjust(32, b'\0')

        # add to configs 
        configs["0x" + admin_addr_slot.hex()] = "0x" + admin_addr_slot_value_bytes.hex()

        # set the `adminRole` to `DEFAULT_ADMIN_ROLE` in `RoleData`
        if account is None: # we set system admin addr as `adminRole`
            admin_role_base_slot = 1
            admin_role_slot = self._bytes_add_num(access_control_storage_default_admin_role_data_slot, admin_role_base_slot)
            default_admin_role = 0x00
            admin_role_slot_value = int_to_big_endian(default_admin_role).rjust(32, b'\0')
            configs["0x" + admin_role_slot.hex()] = "0x" + admin_role_slot_value.hex()
```


2. UpgradeableContractInitializers: Set the `InitializableStorage` as initialized
```python
def _generate_disable_upgradeable_contract_initializers(self, configs: Dict[str, str]):
        """
        struct InitializableStorage {
            /**
             * @dev Indicates that the contract has been initialized.
             */
            uint64 _initialized;
            /**
             * @dev Indicates that the contract is in the process of being initialized.
             */
            bool _initializing;
        }

        // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

        function _disableInitializers() internal virtual {
            // solhint-disable-next-line var-name-mixedcase
            InitializableStorage storage $ = _getInitializableStorage();

            if ($._initializing) {
                revert InvalidInitialization();
            }
            if ($._initialized != type(uint64).max) {
                $._initialized = type(uint64).max;
                emit Initialized(type(uint64).max);
            }
        }
        function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
            bytes32 slot = _initializableStorageSlot();
            assembly {
                $.slot := slot
            }
        }

        function _initializableStorageSlot() internal pure virtual returns (bytes32) {
            return INITIALIZABLE_STORAGE;
        }
        
        """

        initializable_storage_base_slot = "f0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00"
        initializable_storage_base_slot_bytes = bytes.fromhex(initializable_storage_base_slot).rjust(32, b'\0')

        # the `_initialized` and `_initializing` are in the same slot, so we set the value directly here
        # set `_initialized`
        initializable_storage_base_slot_value_of_initialized = 0x1 # version 1 to enable future reinitializers
        initialized_value_bytes_len = len(int_to_big_endian(initializable_storage_base_slot_value_of_initialized))
        initializable_storage_base_slot_value_of_initialized_bytes = int_to_big_endian(initializable_storage_base_slot_value_of_initialized).rjust(32, b'\0')

        # set `_initializing`
        initializable_storage_base_slot_value_of_initializing = 0x0 # false
        # left pad
        left_pad_length = 32 - initialized_value_bytes_len
        initializable_storage_base_slot_value_of_initializing_bytes = int_to_big_endian(initializable_storage_base_slot_value_of_initializing).rjust(left_pad_length, b'\0')
        # right pad. Actually when `_initializing` is false, the value is all-zeros
        initializable_storage_base_slot_value_of_initializing_bytes = initializable_storage_base_slot_value_of_initializing_bytes.ljust(32, b'\0')
        
        # bitwise merge `_initialized` and `_initializing`
        initializable_storage_base_slot_value = self._bytes_bitwise_add(initializable_storage_base_slot_value_of_initialized_bytes, initializable_storage_base_slot_value_of_initializing_bytes)

        configs["0x" + initializable_storage_base_slot_bytes.hex()] = "0x" + initializable_storage_base_slot_value.hex()
```
