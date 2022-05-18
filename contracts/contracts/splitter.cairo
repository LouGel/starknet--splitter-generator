%lang starknet

# Builtins are low-level execution units that perform some predefined computations useful to Cairo programs
#   pedersen is the builtin for Perdern hash computations
#   range_check is useful for numerical comparison operations
# Read more at: https://www.cairo-lang.org/docs/how_cairo_works/builtins.html
%builtins pedersen range_check

# The pedersen builtin is actually of type HashBuiltin, so we need to import that for function declarations
from starkware.cairo.common.cairo_builtins import HashBuiltin

# the math module contains useful math helpers for numerical comparisons, such as assert_le (assert lower-or-equal)
from starkware.cairo.common.math import assert_le

# storage variables are created by declaring empty functions with the @storage_var decorator
# functions with no arguments store a single-value
# functions with arguments work as key-value maps

from starkware.cairo.common.bool import TRUE
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_mul,
    split_64,
    uint256_unsigned_div_rem,
    uint256_add,
)

from starkware.starknet.common.syscalls import get_contract_address

@contract_interface
namespace IERC20:
    func name() -> (name : felt):
    end

    func symbol() -> (symbol : felt):
    end

    func decimals() -> (decimals : felt):
    end

    func totalSupply() -> (totalSupply : Uint256):
    end

    func balanceOf(account : felt) -> (balance : Uint256):
    end

    func allowance(owner : felt, spender : felt) -> (remaining : Uint256):
    end

    func transfer(recipient : felt, amount : Uint256) -> (success : felt):
    end

    func transferFrom(sender : felt, recipient : felt, amount : Uint256) -> (success : felt):
    end

    func approve(spender : felt, amount : Uint256) -> (success : felt):
    end
end

@storage_var
func payee(rank : felt) -> (res : felt):
end

@storage_var
func total_share() -> (res : Uint256):
end
@storage_var
func share(payee : felt) -> (res : Uint256):
end

@storage_var
func payee_len() -> (len : felt):
end

@event
func incremented(inc : felt):
end

######################
func mult256_secured{range_check_ptr}(a : Uint256, b : Uint256) -> (res : Uint256):
    let (result : Uint256, overflow : Uint256) = uint256_mul(a, b)
    assert overflow.low = 0
    assert overflow.high = 0
    return (result)
end
#########################
func cast_felt_to_uint256{range_check_ptr}(x : felt) -> (res : Uint256):
    let (low, high) = split_64(x)
    return (Uint256(low, high))
end

###################################################
func _add_payee{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _payee_address : felt, _share : felt
):
    let (check_share) = share.read(_payee_address)
    assert check_share.low = 0
    assert check_share.high = 0
    let (casted_share) = cast_felt_to_uint256(_share)

    let (len) = payee_len.read()
    payee.write(len, _payee_address)
    share.write(_payee_address, casted_share)
    payee_len.write(len + 1)

    let (total) = total_share.read()
    let (new_total, carry) = uint256_add(total, casted_share)
    total_share.write(new_total)
    return ()
end
####################################################

####################################################
func _set_payees{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _addresses : felt*, _shares : felt*, _len : felt
):
    if _len == 0:
        return ()
    end
    _add_payee(_addresses[_len - 1], _shares[_len - 1])
    _set_payees(_addresses, _shares, _len - 1)
    return ()
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    addresses_len : felt, addresses : felt*, shares_len : felt, shares : felt*
):
    assert addresses_len = shares_len
    _set_payees(addresses, shares, shares_len)

    return ()
end

####################################################
func get_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    balance : Uint256, share : Uint256, total_share : Uint256
) -> (res : Uint256):
    let (ratio, see_you_next_time) = uint256_unsigned_div_rem(share, total_share)
    let (res) = mult256_secured(balance, ratio)
    return (res)
end

####################################################
func _transfer_all{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    token_address : felt, balance : Uint256, rank : felt
):
    if rank == 0:
        return ()
    end
    let (receiver) = payee.read(rank - 1)
    let (receiver_share) = share.read(receiver)
    let (total_share_) = total_share.read()
    let (amount) = get_amount(balance, receiver_share, total_share_)
    let (receiver) = payee.read(rank - 1)

    IERC20.transfer(token_address, receiver, amount)

    _transfer_all(token_address, balance, rank - 1)
    return ()
end

@external
func _release_token_for_all{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    token_address : felt
):
    let (my_address) = get_contract_address()
    let (balance) = IERC20.balanceOf(token_address, my_address)
    let (rank) = payee_len.read()
    _transfer_all(token_address, balance, rank)

    return ()
end
