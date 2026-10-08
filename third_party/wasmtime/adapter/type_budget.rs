//! Count upstream parsed type declarations, including recursive groups and nested scopes.
use wasmparser::{
    ComponentType, ComponentTypeDeclaration, CoreType, InstanceTypeDeclaration,
    ModuleTypeDeclaration, RecGroup,
};

type Result = std::result::Result<(), i32>;
pub struct TypeBudget {
    remaining: u32,
    max_depth: u32,
}
impl TypeBudget {
    pub fn new(maximum: u32, max_depth: u32) -> Self {
        Self {
            remaining: maximum,
            max_depth,
        }
    }
    fn charge(&mut self, amount: usize) -> Result {
        let amount = u32::try_from(amount).map_err(|_| -3)?;
        if amount > self.remaining {
            return Err(-3);
        }
        self.remaining -= amount;
        Ok(())
    }
    fn depth(&self, depth: u32) -> Result {
        if depth > self.max_depth {
            Err(-3)
        } else {
            Ok(())
        }
    }
    pub fn group(&mut self, group: &RecGroup) -> Result {
        self.charge(group.types().len())
    }
    pub fn core(&mut self, ty: &CoreType<'_>, depth: u32) -> Result {
        self.depth(depth)?;
        match ty {
            CoreType::Rec(group) => self.group(group),
            CoreType::Module(declarations) => {
                self.charge(1)?;
                for declaration in declarations {
                    match declaration {
                        ModuleTypeDeclaration::Type(group) => self.group(group)?,
                        _ => self.charge(1)?,
                    }
                }
                Ok(())
            }
        }
    }
    pub fn component(&mut self, ty: &ComponentType<'_>, depth: u32) -> Result {
        self.depth(depth)?;
        self.charge(1)?;
        match ty {
            ComponentType::Component(declarations) => {
                for declaration in declarations {
                    match declaration {
                        ComponentTypeDeclaration::Type(child) => {
                            self.component(child, depth + 1)?
                        }
                        ComponentTypeDeclaration::CoreType(child) => self.core(child, depth + 1)?,
                        _ => self.charge(1)?,
                    }
                }
            }
            ComponentType::Instance(declarations) => {
                for declaration in declarations {
                    match declaration {
                        InstanceTypeDeclaration::Type(child) => self.component(child, depth + 1)?,
                        InstanceTypeDeclaration::CoreType(child) => self.core(child, depth + 1)?,
                        _ => self.charge(1)?,
                    }
                }
            }
            _ => {}
        }
        Ok(())
    }
}
