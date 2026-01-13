use array::{Array, ArrayTrait, Span, SpanTrait};
use option::OptionTrait;
use serde::Serde;
use starknet::{SyscallResult, Store, StorageBaseAddress};
use traits::{Into, TryInto};

use influence::common::{access, packed, position};
use influence::config::{entities, errors};

#[derive(Copy, Drop, Serde)]
struct Entity {
    label: u64,
    id: u64
}

trait EntityTrait {
    fn new(label: u64, id: u64) -> Entity;
    fn path(self: Entity) -> Span<felt252>;
    fn is_empty(self: Entity) -> bool;

    // Positioning
    fn from_position(asteroid: u64, lot: u64) -> Entity;
    fn to_position(self: Entity) -> (u64, u64);

    // Access
    fn controller(self: Entity) -> Entity;
    fn controls(self: Entity, entity: Entity) -> bool;
    fn assert_controls(self: Entity, entity: Entity);
    fn can(self: Entity, entity: Entity, permission: u64) -> bool;
    fn assert_can(self: Entity, entity: Entity, permission: u64);
    fn can_until(self: Entity, entity: Entity, permission: u64, until: u64) -> bool;
    fn assert_can_until(self: Entity, entity: Entity, permission: u64, until: u64);
}

impl EntityIntoFelt252 of Into<Entity, felt252> {
    #[inline(always)]
    fn into(self: Entity) -> felt252 {
        return self.label.into() + self.id.into() * 65536;
    }
}

impl Felt252TryIntoEntity of TryInto<felt252, Entity> {
    #[inline(always)]
    fn try_into(self: felt252) -> Option<Entity> {
        let (id, label) = integer::u128_safe_divmod(
            self.try_into().unwrap(), 65536_u128.try_into().unwrap() // 2 ^16
        );

        return Option::Some(Entity {
            label: label.try_into().unwrap(), id: id.try_into().unwrap()
        });
    }
}

impl U128TryIntoEntity of TryInto<u128, Entity> {
    #[inline(always)]
    fn try_into(self: u128) -> Option<Entity> {
        let (id, label) = integer::u128_safe_divmod(self, 65536_u128.try_into().unwrap());

        return Option::Some(Entity {
            label: label.try_into().unwrap(),
            id: id.try_into().unwrap()
        });
    }
}

impl EntityIntoU128 of Into<Entity, u128> {
    #[inline(always)]
    fn into(self: Entity) -> u128 {
        return self.label.into() + self.id.into() * 65536;
    }
}

impl EntityImpl of EntityTrait {
    fn new(label: u64, id: u64) -> Entity {
        return Entity { id: id, label: label };
    }

    fn path(self: Entity) -> Span<felt252> {
        return array![self.into()].span();
    }

    fn is_empty(self: Entity) -> bool {
        return self.id == 0;
    }

    fn from_position(asteroid: u64, lot: u64) -> Entity {
        let mut id: u128 = asteroid.into();
        packed::pack_u128(ref id, packed::EXP2_32, packed::EXP2_32, lot.into());
        position::assert_valid_lot(asteroid, lot);
        return EntityTrait::new(entities::LOT, id.try_into().unwrap());
    }

    fn to_position(self: Entity) -> (u64, u64) {
        return position::position_of(self);
    }

    fn controller(self: Entity) -> Entity {
        let controller = access::controller_of(self).expect(errors::CONTROL_NOT_FOUND);
        return controller;
    }

    fn controls(self: Entity, entity: Entity) -> bool {
        return access::controls(self, entity);
    }

    fn assert_controls(self: Entity, entity: Entity) {
        access::assert_controls(self, entity);
    }

    fn can(self: Entity, entity: Entity, permission: u64) -> bool {
        return access::can(self, entity, permission);
    }

    fn assert_can(self: Entity, entity: Entity, permission: u64) {
        access::assert_can(self, entity, permission);
    }

    fn can_until(self: Entity, entity: Entity, permission: u64, until: u64) -> bool {
        return access::can_until(self, entity, permission, until);
    }

    fn assert_can_until(self: Entity, entity: Entity, permission: u64, until: u64) {
        access::assert_can_until(self, entity, permission, until);
    }
}

impl EntityDefault of Default<Entity> {
    #[inline(always)]
    fn default() -> Entity {
        return Entity { id: 0, label: 0 };
    }
}

impl EntityPartialEq of PartialEq<Entity> {
    #[inline(always)]
    fn eq(lhs: @Entity, rhs: @Entity) -> bool {
        return (*lhs.id == *rhs.id) && (*lhs.label == *rhs.label);
    }

    #[inline(always)]
    fn ne(lhs: @Entity, rhs: @Entity) -> bool {
        return (*lhs.id != *rhs.id) || (*lhs.label != *rhs.label);
    }
}
