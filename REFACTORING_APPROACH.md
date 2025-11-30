# MountController Refactoring - Implementation Approach

## Current State
- Original `mount_controller.gd`: **1392 lines**
- Single file handling: movement, weapons, input, HUD, attacks, pickups

## New Component Architecture

### Components Created ✅
1. **WeaponManager** - Weapon lifecycle management (~420 lines)
2. **WeaponInputHandler** - Input tracking (~110 lines)
3. **WeaponHUDManager** - HUD management (~200 lines)
4. **WeaponAttackCoordinator** - Attack execution (~180 lines)

### Refactored MountController (Target)
- **Estimated size**: ~400-500 lines (down from 1392)
- **Focus**: Movement/physics + component coordination

## Refactoring Strategy

### Phase 1: Component Integration (Recommended First Step)

The refactored `mount_controller.gd` should:

1. **Initialize Components** (in `_ready()`):
   ```gdscript
   # Create component nodes
   var weapon_manager = WeaponManager.new()
   var input_handler = WeaponInputHandler.new()
   var hud_manager = WeaponHUDManager.new()
   var attack_coordinator = WeaponAttackCoordinator.new()
   
   # Add as children
   add_child(weapon_manager)
   add_child(input_handler)
   add_child(hud_manager)
   add_child(attack_coordinator)
   
   # Initialize with dependencies
   weapon_manager.initialize(self, slot_manager, logger)
   input_handler.initialize(self, logger)
   hud_manager.initialize(self, logger)
   attack_coordinator.initialize(self, weapon_manager, logger)
   ```

2. **Connect Component Signals**:
   ```gdscript
   # WeaponManager signals
   weapon_manager.hud_update_needed.connect(_on_hud_update_needed)
   weapon_manager.weapon_dropped.connect(_on_weapon_dropped)
   
   # InputHandler signals
   input_handler.primary_attack_requested.connect(attack_coordinator.attack_with_slot)
   input_handler.secondary_attack_started.connect(attack_coordinator.start_secondary_attack)
   input_handler.secondary_attack_released.connect(attack_coordinator.release_secondary_attack)
   ```

3. **Delegate to Components**:
   - All weapon operations → `weapon_manager`
   - All input handling → `input_handler`
   - All HUD operations → `hud_manager`
   - All attack execution → `attack_coordinator`

### Phase 2: Remove Duplicate Code

After components are integrated and tested:
- Remove old weapon management methods
- Remove old input handling methods
- Remove old HUD management methods
- Remove old attack methods

### Phase 3: Clean Up

- Update public API methods to delegate to components
- Ensure all signals are properly connected
- Test all functionality

## What Stays in MountController

1. **Movement/Physics** (`_integrate_forces`) - Core mount behavior
2. **Pickup Connection Logic** - Mount-specific coordination
3. **Public API Methods** - Called by UI/external systems (delegate internally)
4. **Component Lifecycle** - Initialization and signal connections

## Migration Checklist

- [ ] Create component instances in `_ready()`
- [ ] Connect all component signals
- [ ] Update pickup handler to use WeaponManager
- [ ] Update public methods (replace_weapon_in_slot, etc.) to delegate
- [ ] Remove old weapon management code
- [ ] Remove old input handling code
- [ ] Remove old HUD management code
- [ ] Remove old attack code
- [ ] Test weapon attachment
- [ ] Test weapon upgrades
- [ ] Test weapon replacement
- [ ] Test weapon dropping
- [ ] Test primary attacks
- [ ] Test secondary attacks
- [ ] Test HUD updates
- [ ] Test pickup prompts

## Testing Strategy

1. **Unit Testing**: Test each component independently
2. **Integration Testing**: Test component interactions
3. **Functional Testing**: Test all game features
4. **Performance Testing**: Ensure no performance regression

## Rollback Plan

If issues arise:
- Keep old `mount_controller.gd` as backup
- Components can work standalone
- Can revert to old structure if needed

